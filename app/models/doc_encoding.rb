class DocEncoding < Ohm::Model
  attribute :filename
  attribute :filepath
  attribute :state
  attribute :started_encoding_at
  attribute :finished_encoding_at
  attribute :client_id
  attribute :profile_id
  attribute :doc_id
  attribute :container
  
  # AASM 
  # ===================
  #aasm_column :state
  aasm.attribute_name :state
  
  # States
  #aasm_state  :created
  #aasm_state  :processed, :enter  => :perform_encoding
  #aasm_state  :uploaded, :enter => :perform_upload
  #aasm_state  :completed, :after_enter => :perform_cleanup_and_notification
  #aasm_state  :failed
  #aasm_initial_state  :created

  aasm column: 'status', no_direct_assignment: true, requires_lock: true do
    state :created, initial: true
    state :processed, :enter  => :perform_encoding
    state :uploaded, :enter => :perform_upload
    state :completed, :after_enter => :perform_cleanup_and_notification
    state  :failed
    #after_all_transitions :generate_status_transition_log!
    # State Event Definitions  
    event :process do
      transitions :to => :processed, :from => [:created]
    end

    event :upload do
      transitions :to => :uploaded, :from => [:processed]
    end

    event :complete do
      transitions :to => :completed, :from => [:uploaded]
    end

    event :fail do
      transitions :to => :failed, :from => [:created, :queued, :processed, :uploaded, :encoded, :complete]
    end
  end
  
  # Associations
  # ====================

  def client
    @client ||= Client[self.client_id]
  end
  
  def profile
    @profile ||= Profile[self.profile_id]
  end
  
  def doc
    @doc ||= Doc[self.doc_id]
  end
  
  
  # Validations
  # ====================
  def validate
    assert_present  :state
  end
  
  
  # Sets the Resque Queue
  @queue = :encodings
  
  
  # Class Methods
  # ====================
  
  def self.create_for_doc_and_profile(doc, profile)
    params = { :state => "created", :filename => self.generate_encoding_filename(doc.basename, profile) }
    #params = { :state => "created", :filename => self.generate_videoname(video.basename) }
    ve = create params.merge(:client_id => doc.client.id, :doc_id => doc.id, :profile_id => profile.id)
    return ve
  end
  
  def self.perform(vid_encoding_id)
    doc_encoding = self[vid_encoding_id]
    doc_encoding.process!
    doc_encoding.upload!
    doc_encoding.complete!
  end
  
  def self.delete_from_local(vid_encoding_id)
    ve = self[vid_encoding_id]
    message = "VideoEncoding.delete_from_local: " + ve.id.to_s
    defined?(logger) ? logger.warn(message) : $stderr.puts(message)
    
    case ve.container
    when /ts/
      tsdir = File.dirname("public/" + ve.filepath)  if !ve.filepath.nil?
      Store.rmdir_from_local(tsdir)
      message = "VideoEncoding.delete_from_local - filedir: " + tsdir
      defined?(logger) ? logger.warn(message) : $stderr.puts(message)
    else
      if !ve.filepath.nil?
        Store.delete_from_local("public/" + ve.filepath)  
        message = "VideoEncoding.delete_from_local : " + ve.filepath
        defined?(logger) ? logger.warn(message) : $stderr.puts(message)
      end
    end
    #ve.delete
  end
  
  # State Events
  # ====================
  
  def perform_encoding_flv
    doc, profile = self.doc, self.profile
    begin
      RVideo::Transcoder.logger = logger
      transcoder = RVideo::Transcoder.new(doc.filepath)
      
      #recipe = profile.is_flash? ? profile.video_command.concat(" \nflvtool2 -U $output_file$") : profile.video_command
      recipe = profile.doc_command
      self.update(:started_encoding_at => Time.now, :container => profile.container) # 'flv'
           
      #transcoder.execute(recipe, recipe_options(video.filepath, encoding_filepath, profile))
      roptions = recipe_options(doc.filepath, encoding_filepath, profile)
      transcoder.execute(recipe, roptions)
      # recipe : ffmpeg -i $input_file$ -ar 22050 -f flv -r 24 -y $output_file$
      # roptions : {:input_file=>"/home/vagrant/panda/public/data/tmp_uploads/0000000010_src2.mp4", :output_file=>"public/data/tmp_videos/59/src2_HD.flv", :container=>"flv", :video_bitrate_in_bits=>"409600", :fps=>"24", :audio_bitrate=>"48", :audio_bitrate_in_bits=>"49152", :resolution_and_padding=>"-s 480x360 "}
      
      #self.update(:finished_encoding_at => Time.now, :filepath => encoding_filepath)
      tmpath = encoding_filepath.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}
      tmpath.shift
      self.update(:finished_encoding_at => Time.now, :filepath => tmpath.join(File::SEPARATOR))
      
    rescue
      self.fail!
    end    
  end
  
  def perform_encoding_segment
    doc, profile = self.doc, self.profile
    basename = docname = doc_filename(doc.basename)
    
    begin
      transcoder = RVideo::Transcoder.new(doc.filepath)
      RVideo::Transcoder.logger = logger

      recipe = profile.doc_command
      
      self.update(:started_encoding_at => Time.now, :container => profile.container) #'ts'
      
      #roptions = segment_options(basename, video.id, videoname, video.filepath, segment_list_filepath, profile, segment_output_filepath)
      #transcoder.execute(recipe, roptions)
      ## segment_list_filepath # public/data/hls/218/Big_Buck_Bunny_480p.m3u8
      #tmpath = segment_list_filepath.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}
      #tmpath.shift
      self.update(:finished_encoding_at => Time.now, :filepath => tmpath.join(File::SEPARATOR))
      
    rescue Exception => e
      self.fail!
    end    
  end
  
  def perform_encoding
    doc, profile = self.doc, self.profile
    case profile.container
    when /flv/
      perform_encoding_flv
    when /ts/
      perform_encoding_segment
    else
      perform_encoding_flv
    end
  end
  
  def perform_encoding_streamio_ffmpeg
    # new ffmpeg
    movie = FFMPEG::Movie.new(video.filepath)
    self.update(:started_encoding_at => Time.now)
    movie.transcode(encoding_filepath, " -ar 22050 -f flv -r 24 ")
   
    #raise "Encoding Filepath " + encoding_filepath # public/data/tmp_videos/38/src3_HD.flv
    tmpath = encoding_filepath.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}
    tmpath.shift
    #self.update(:finished_encoding_at => Time.now, :filepath => encoding_filepath)
    self.update(:finished_encoding_at => Time.now, :filepath => tmpath.join(File::SEPARATOR))
  end
  
  def perform_upload
    # jk: no upload
    #Store.set_to_s3(self.s3_filename, self.filepath, client_s3_bucket)
  end
  
  def perform_cleanup_and_notification
    # jk: no delete & no update
    #Store.delete_from_local(self.filepath)
    #self.update(:filepath => s3_path) 
    self.doc.complete!
  end
  
  
  
  def recipe_options(input_file, output_file, profile)
    {
      :input_file => input_file,
      :output_file => output_file,
      :container => profile.container, 
      :video_bitrate_in_bits => profile.video_bitrate_in_bits.to_s, 
      :fps => profile.fps,
      :audio_bitrate => profile.audio_bitrate.to_s, 
      :audio_bitrate_in_bits => profile.audio_bitrate_in_bits.to_s, 
      :resolution_and_padding => calculate_resolution_padding_and_cropping
    }
  end
  
  def segment_options(basename, videoid, videoname, input_file, segment_list_file, profile, segment_part_file)
    {
      :basename => basename,
      :videoid => videoid,
      :videoname => videoname,
      :input_file => input_file,
      :segment_file => segment_part_file,
      :output_file => segment_list_file,
      :container => profile.container, 
      :video_bitrate_in_bits => profile.video_bitrate_in_bits.to_s, 
      :fps => profile.fps,
      :audio_bitrate => profile.audio_bitrate.to_s, 
      :audio_bitrate_in_bits => profile.audio_bitrate_in_bits.to_s, 
      :resolution_and_padding => calculate_resolution_padding_and_cropping
    }
  end
  
  def error_messages
    self.errors.present do |e|
      e.on [:state, :not_present], "State must be present"
    end
  end
  
  
  # Convenience methods
  # ======================
  
  #def client_s3_bucket
  #  self.client.s3_bucket_name
  #end
  
  def thumbnail_path
    self.doc.thumbnail_filepath
  end
  
  #def s3_filename
  #  [self.video.s3_dirname, self.filename].join("/")
  #end
  
  def to_json
    self.attributes_with_values.to_json
  end
  
      
private  

  def encoding_filepath
    File.join(monk_settings(:temp_video_filepath), self.doc_id, self.filename)
  end
  
  def doc_filename(original_doc_filename)
    original_doc_filename.gsub(Regexp.new(/#{File.extname(original_doc_filename)}\Z/), "")
  end
  
  def hls_filepath
      hlsdirectory = File.join(monk_settings(:hls_video_filepath), self.video_id.to_s)
      FileUtils.mkdir(hlsdirectory, :mode => 0777) unless File.directory?(hlsdirectory)
      hlsdirectory
  end
  
  def segment_filepath
    videoname = video_filename(video.basename)   # Simpsons
    segment_name = videoname + profile.encoded_filename_suffix # Simpsons-%d.ts
    File.join(monk_settings(:temp_video_filepath), self.video_id, segment_name)
  end
  
  def segment_list_filepath
    videoname = video_filename(video.basename)   # Simpsons
    #File.join(monk_settings(:hls_video_filepath), self.video_id, "#{videoname}.m3u8")
    File.join(hls_filepath, "#{videoname}.m3u8")
  end
  
  def segment_output_filepath
    videoname = video_filename(video.basename)   # eg: Simpsons
    segment_name = videoname + profile.encoded_filename_suffix # Simpsons-%d.ts
    File.join(monk_settings(:hls_video_filepath), self.video_id, segment_name)
  end
  
  #def s3_path
  #  [monk_settings(:s3_base_url), client_s3_bucket, self.s3_filename].join("/")
  #end
  
  # http://github.com/newbamboo/panda/blob/sinatra/lib/db/encoding.rb
  def calculate_resolution_padding_and_cropping
    video, profile = self.video, self.profile
    in_w = video.width.to_f
    in_h = video.height.to_f
    out_w = profile.width.to_f
    out_h = profile.height.to_f
    
    begin
      raise RuntimeError if (in_h.zero? || in_w.zero?)
      aspect = in_w / in_h
      aspect_inv = in_h / in_w
    rescue
      return %(-s #{profile.width}x#{profile.height} )
    end

    height = (out_w / aspect.to_f).to_i
    height -= 1 if height % 2 == 1

    opts_string = %(-s #{profile.width}x#{height} )

    # Keep the video's original width if the video height is greater than profile height
    if height > out_h
      width = (out_h / aspect_inv.to_f).to_i
      width -= 1 if width % 2 == 1

      opts_string = %(-s #{width}x#{profile.height} )
    # Otherwise letterbox it
    elsif height < out_h
      pad = ((out_h - height.to_f) / 2.0).to_i
      pad -= 1 if pad % 2 == 1
      opts_string << %(-padtop #{pad} -padbottom #{pad})
    end

    return opts_string
  end
  
  def self.generate_encoding_filename(original_doc_filename, profile_data)
    suffix = profile_data.encoded_filename_suffix
    ext = profile_data.container
    original_doc_filename.gsub(Regexp.new(/#{File.extname(original_doc_filename)}\Z/), "") + "_#{suffix}.#{ext}"
  end
  
  def self.generate_videoname(original_doc_filename)
    original_doc_filename.gsub(Regexp.new(/#{File.extname(original_doc_filename)}\Z/), "")
  end
  
end
