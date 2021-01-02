require 'yaml'
#require "unix_crypt"

#use Rack::Session::Cookie, secret: "irnd;ufndto.ent[fnt"

class Main

  get "/" do
    #protected!
    @redis = monk_settings(:redis)
    @clients = Client.all.sort
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
  
  # Client Videos
  # ====================================
  
  get "/admin/clients/:id/videos" do
    #protected!
    @client = Client[params[:id]]
    @videos = @client.videos.sort(:order => 'DESC')
    haml :videos, :layout => !request.xhr?
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
  
end
