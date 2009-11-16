require 'gitgo/controller'

module Gitgo
  module Controllers
    class Repo < Controller
      set :resource_name, "repo"
      set :views, "views/repo"
      
      get("/") do 
        erb :index, :locals => {
          :stats => repo.stats,
          :keys => repo.list
        }
      end
      
      get("/indicies")             { indicies }
      get("/indicies/:key")        {|key| indicies(key) }
      get("/indicies/:key/:value") {|key, value| indicies(key, value) }
      
      get("/status") do
        erb :status, :locals => {:status => repo.status}
      end
      
      get("/fsck") do
        erb :fsck, :locals => {:issues => repo.fsck}
      end
      
      post("/commit") do
        repo.commit request['message']
        redirect url("status")
      end
      
      post("/reindex") do
        repo.reindex! set?('full')
        redirect url
      end
      
      post("/reset") do
        repo.reset
        redirect url("status")
      end
      
      def indicies(key=nil, value=nil)
        erb :indicies, :locals => {
          :current_key => key,
          :keys => repo.list,
          :current_value => value,
          :values => key ? repo.list(key) : [],
          :shas => key && value ? repo.index(key, value) : []
        }
      end
    end
  end
end