class Doc < Ohm::Model
  attribute :filename
  attribute :filepath

  attribute :video_codec
  attribute :video_bitrate
  attribute :audio_codec
  attribute :audio_sample_rate
  attribute :thumbnail_filename
  attribute :thumbnail_filepath
  attribute :duration
  attribute :container
  attribute :width
  attribute :height
  attribute :fps

  attribute :state
  attribute :error_msg
  attribute :client_id
  
  attr_accessor :size, :content_type, :md5
  
  
  # AASM 
  # ===================
  aasm.attribute_name :state
  
  # States
  #aasm_state  :created
  #aasm_state  :queued, :enter => :perform_file_checkout
  #aasm_state  :processed, :enter  => :perform_processing
  #aasm_state  :uploaded, :enter => :perform_upload
  #aasm_state  :encoded, :enter => :perform_encoding
  #aasm_state  :completed, :enter => :perform_cleanup_and_notification
  #aasm_state  :failed, :enter => :perform_error_notification
  #aasm_initial_state  :created

  aasm column: 'status', no_direct_assignment: true, requires_lock: true do
    state :created, initial: true
    state :queued, :enter => :perform_file_checkout
    state :processed, :enter  => :perform_processing
    state :uploaded, :enter => :perform_upload
    state :encoded, :enter => :perform_encoding
    state :completed, :enter => :perform_cleanup_and_notification
    state :failed, :enter => :perform_error_notification
    #after_all_transitions :generate_status_transition_log!
    # State Event Definitions
    event :queue do
      transitions :to => :queued, :from => [:created]
    end

    event :process do
      transitions :to => :processed, :from => [:queued]
    end

    event :upload do
      transitions :to => :uploaded, :from => [:processed]
    end

    event :encode do
      transitions :to => :encoded, :from => [:uploaded]
    end

    event :complete do
      transitions :to => :completed, :from => [:encoded], :guard => :docs_finished_encoding?
    end

    event :fail do
      transitions :to => :failed, :from => [:created, :queued, :processed, :uploaded, :encoded, :complete]
    end
  end
  
  # Associations
  # ====================
  
  set :doc_encodings, DocEncoding
  set :notifications, Notification
  
  def client
    @client ||= Client[self.client_id]
  end
  
  
  # Validations
  # ====================
  
  def validate
    assert_present  :state
  end
  
  # Sets the Resque Queue
  @queue = :docs
  
  
  # Class Methods
  # ====================
  
  # Video.create_on(action, params, client)
  # A wrapper for the create method, this will set the initial state of the video object based
  # on the action specified. It will also associate itself with the client.
  # On action :upload, the method performs file manipulation in order to prepare the video file for
  # further processing.
  # Finally, it places the video into the Resque queue.
  def self.create_on(action, params, client)
    params ||= {}
    params.symbolize_keys!
    doc = case action.to_sym
    when :upload
      begin
        # TODO: Move to a state transition event so that it can run in the background
        ##new_filename = params[:filename].strip.gsub(/[^A-Za-z\d\.\-_]+/, '_')
        new_filename = params[:filename]

        logger.debug("Document/create_on: new_filename: #{new_filename}")

        new_filepath = [params[:filepath], new_filename].join('_')
        logger.warn "new_filepath: #{new_filepath}"

        FileUtils.mv(params[:filepath], new_filepath)
        params.merge!(:filename => new_filename, :filepath => new_filepath)
      rescue Exception => e
        logger.debug("Preparing files failed: #{e}")
      end
      create params.merge(:state => "queued", :client_id => client.id)
    when :encode
      create params.merge(:state => "created", :client_id => client.id)
    end
    
    logger.debug
    client.docs.add doc
    Resque.enqueue(Doc, doc.id)
    return doc
  end
    
  def self.perform(doc_id)
    doc = self[doc_id]
    case doc.state
      when "created"
        doc.queue!
        doc.process!
        doc.upload!
        doc.encode!
      when "queued"
        doc.process!
        doc.upload!
        doc.encode!
    end
  end

  def self.delete_with_doc_encodings(doc_id)
    doc = self[doc_id]
    message = "doc_delete : " + doc.id.to_s
    defined?(logger) ? logger.info(message) : $stderr.puts(message)
    # delete doc_encoding
    doc.doc_encodings.each do |doc_encoding|
      DocEncoding.delete_from_local(doc_encoding.id)
      #//raise "Remove video_encoding: " + video_encoding.id.to_s
      #video.video_encodings.delete(video_encoding)
      doc_encoding.delete
      #rescue StandardError => bang
      #  print "Error running script: " + bann
      #end
    end
    # delete doc
    Store.delete_from_local(doc.filepath)
    Store.delete_from_local("public/" + doc.thumbnail_filepath) if !doc.thumbnail_filepath.nil?
    #return client
  end
  
  # State Events
  # ====================
  
  def perform_file_checkout
    #self.update(:filepath => temp_doc_filepath)
    #Store.get_from_s3(self.filename, self.filepath, client_s3_bucket)
  end
  
  def perform_processing
    inspector = RVideo::Inspector.new(:file => self.filepath)
    raise "Format Not Recognized" unless inspector.valid? and inspector.doc?
    
    #self.update( 
    #  :video_codec => (inspector.video_codec rescue nil),
    #  :video_bitrate => (inspector.bitrate rescue nil),
    #  :audio_codec => (inspector.audio_codec rescue nil),
    #  :audio_sample_rate => (inspector.audio_sample_rate rescue nil),
    #  :duration => (inspector.duration rescue nil),
    #  :container => (inspector.container rescue nil),
    #  :width => (inspector.width rescue nil),
    #  :height => (inspector.height rescue nil),
    #  :fps => (inspector.fps rescue nil),
    #  :thumbnail_filename => generate_thumbnail_filename
    #)
    
    #RVideo::Transcoder.logger = logger
    #inspector.capture_frame("5%", temp_thumbnail_filepath)
    ##raise "Temp Thumbnail Filepat " + temp_thumbnail_filepath           # public/data/tmp_videos/23/src1_thumb.jpg
    ##raise "Generate Thumbnail Filename " + generate_thumbnail_filename  # src3_thumb.jpg
    ##tmpa = "public/data/tmp_videos/26/src1_thumb.jpg".split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}
    #tmpath = temp_thumbnail_filepath.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}
    #tmpath.shift
    ##self.update(:thumbnail_filepath => temp_thumbnail_filepath)
    #self.update(:thumbnail_filepath => tmpath.join(File::SEPARATOR))
  end
  
  def perform_upload
    # upload the file to S3 unless it already exists on s3
    # upload the generated thumbnail to S3
#jk:temp not upload
    #Store.set_to_s3(s3_filename, self.filepath, client_s3_bucket) unless Store.file_exists?(:s3, self.filename, client_s3_bucket)
    #Store.set_to_s3(s3_thumbnail_filename, self.thumbnail_filepath, client_s3_bucket)
  end
  
  def perform_encoding
    create_encodings
    encode_videos
  end
  
  def perform_cleanup_and_notification
    #jk: no delete * no update
    #Store.delete_from_local(self.filepath)
    #Store.delete_from_local(self.thumbnail_filepath)
    #self.update(:filepath => s3_video_path, :thumbnail_filepath => s3_thumbnail_path)
    
    #create_and_queue_notifications unless self.client_notification_url.blank?
    create_and_queue_notifications unless self.client_notification_url.to_s == ''
  end
  
  def perform_error_notification
    create_and_queue_notifications unless self.client_notification_url.blank?
  end
  
  def create_and_queue_notifications
    notification = Notification.create :state => 'created', :doc_id => self.id
    self.notifications.add notification
    Resque.enqueue(Notification, notification.id)
  end
  
  
  # Instance Methods
  # =========================
  
  def error_messages
    self.errors.present do |e|
      e.on [:state, :not_present], "State must be present"
    end
  end
  
  
  # Guards 
  # =========================
  
  def docs_finished_encoding?
    finished_encoding = true
    encoding_container = ""
    self.doc_encodings.each do |doc_encoding|
#raise "videos_finished_encoding? : video_encoding.completed? " + video_encoding.completed?.to_s
#raise "videos_finished_encoding? : video_encoding.id " + video_encoding.id.to_s
      finished_encoding = false unless doc_encoding.completed?
      encoding_container = doc_encoding.container
    end
    #raise "videos_finished_encoding? : finished_encoding " + finished_encoding.to_s
    message = "docs_finished_encoding? : " + container + ", finished_encoding: " + finished_encoding.to_s
    defined?(logger) ? logger.info(message) : $stderr.puts(message)
    return finished_encoding
  end
  
  
  # Convenience Methods
  # =========================
  
  #def s3_filename
  #  [self.s3_dirname, self.basename].join("/")
  #end
  
  def s3_thumbnail_filename
    [self.s3_dirname, self.thumbnail_filename].join("/")
  end
  
  def s3_dirname
    ['panda_videos', self.id.to_s].join("/")
  end
      
  def client_s3_bucket
    self.client.s3_bucket_name
  end
  
  def client_notification_url
    self.client.notification_url
  end
      
  def to_json(include_encodings=false)
    unless include_encodings
      return self.attributes_with_values.to_json
    else
      return self.attributes_with_values.merge(:encodings => self.doc_encodings.collect { |ve| ve.attributes_with_values }).to_json
    end
  end
  
  def basename
    logger.warn "self.filename: #{self.filename}"
    File.basename(self.filename)
  end
  
  # Private Methods
  # =========================
  
private

  def temp_doc_filepath
    directory = File.join(monk_settings(:temp_doc_filepath), self.id.to_s)
    FileUtils.mkdir(directory, :mode => 0777) unless File.directory?(directory)
    File.join(directory, self.basename)
  end
  
  def temp_thumbnail_filepath
    directory = File.join(monk_settings(:temp_doc_filepath), self.id.to_s)
    FileUtils.mkdir(directory, :mode => 0777) unless File.directory?(directory)
    File.join(directory, self.thumbnail_filename)
  end
  
  #def s3_video_path
  #  [monk_settings(:s3_base_url), client_s3_bucket, self.s3_filename].join("/")
  #end
  
  def s3_thumbnail_path
    [monk_settings(:s3_base_url), client_s3_bucket, self.s3_thumbnail_filename].join("/")
  end
  
  def create_encodings
    self.client.profiles.each do |profile|
      doc_encoding = DocEncoding.create_for_doc_and_profile(self, profile)
      self.client.doc_encodings.add doc_encoding
      self.doc_encodings.add doc_encoding
    end
  end
    
  def encode_docs
    self.doc_encodings.each do |ve|
      Resque.enqueue(DocEncoding, ve.id)
    end
  end
  
  def generate_thumbnail_filename(ext = "jpg")
    self.basename.gsub(Regexp.new(File.extname(self.filename)), "") << "_thumb" << ".#{ext}"
  end
end
