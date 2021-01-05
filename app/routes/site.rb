require 'yaml'
require "unix_crypt"

#use Rack::Session::Cookie, secret: "irnd;ufndto.ent[fnt"

class Main

  get "/" do
    #protected!
    @redis = monk_settings(:redis)
    @clients = Client.all.sort
    #logger.warn '@clients:' << @clients.inspect
    #if authenticated?
      @successlogin = "Admin"
      haml :clients, :layout => !request.xhr?
    #else
    #  @successlogin = nil
    #  haml :home
    #  #haml :client_list, :layout => !request.xhr?
    #end
  end
  
  get "/admin/clients/new" do
    #protected!
    haml :new_client, :layout => !request.xhr?
  end
  
  post "/admin/clients" do
    #protected!
    @client = Client.create_with_default_profiles(params[:client])
    @client.to_json
  end
  
  delete "/admin/clients/:id" do
    protected!
    @client = Client[params[:id]]
    @client.delete
    @client.to_json
  end
  
  get "/admin/clients/:id/edit" do
    #protected!
    @client = Client[params[:id]]
    haml :edit_client, :layout => !request.xhr?
  end
  
  put "/admin/clients/:id" do
    #protected!
    @client = Client[params[:id]]
    @client.update(params[:client])
    @client.to_json
  end
  
  
  # Client Profiles
  # ====================================
  
  get "/admin/clients/:id/profiles" do
    #protected!
    @client = Client[params[:id]]
    @profiles = @client.profiles
    haml :profiles, :layout => !request.xhr?
  end
  
  # Client Documents
  # ====================================
  
  get "/admin/clients/:id/videos" do
    #protected!
    @client = Client[params[:id]]
    @docs = @client.docs.sort(:order => 'DESC')
    haml :documents, :layout => !request.xhr?
  end
  
  delete "/admin/clients/:id/videos/:video_id" do
    #protected!
    @client = Client[params[:id]]
    @video = @client.videos.find_by_id(params[:video_id])
    Video.delete_with_video_encodings(params[:video_id])
    @client.delete_video(params[:video_id])
    @video.delete
    @client.to_json
  end

  get "/admin/clients/:id/upload" do
    #ensure_video(:local)
    $pwd = ENV['PWD']
    doc_path = File.join($pwd, 'test.docx')
    #logger.warn("doc_path: #{doc_path}")
    tmp_doc_hash = { :filename => "test.docx", :filepath => doc_path }
    params[:video] = tmp_doc_hash

    logger.warn("params: #{params.inspect}")
    #logger.debug("params[:video][:filename] #{params[:video][:filename]}")
    tmp_filename = File.join($pwd, 'test.docx')

    client = Client[params[:id]]
    video = Doc.create_on(:upload, params[:video], client)
    #respond_with_success(:video => video.to_json)
  end
  
  def ensure_video(stored = :local)
    begin
      if stored == :local
        required_params(params[:video], :filepath)
        raise(StandardError, "Video file does not exist") unless Store.file_exists?(:local, params[:video][:filepath])
      end
    rescue Exception => e
      content_type :json
      respond_with_error(2, e.message)
    end     
  end

end
