require 'gitgo/controller'
require 'gitgo/controllers/code'
require 'gitgo/controllers/issue'
require 'gitgo/controllers/repo'
require 'gitgo/controllers/wiki'

module Gitgo
  class Server < Controller
    set :views, File.expand_path("views/server", ROOT)
    set :static, true
    
    get('/')         { timeline }
    get('/timeline') { timeline }
    
    use Controllers::Code
    use Controllers::Issue
    use Controllers::Wiki
    use Controllers::Repo
    
    def timeline
      page = (request[:page] || 0).to_i
      per_page = (request[:per_page] || 5).to_i
      
      author = request[:author].to_s
      timeline = repo.current.nil? ? nil : begin
        repo.timeline(:n => per_page, :offset => page * per_page) do |sha|
          author.empty? || docs[sha].author.email == author
        end.collect do |sha|
          docs[sha]
        end.sort_by do |doc|
          doc.date
        end
      end
      
      erb :timeline, :locals => {
        :page => page,
        :per_page => per_page,
        :author => author,
        :timeline => timeline,
        :authors => repo.list('author')
      }
    end
  end
end