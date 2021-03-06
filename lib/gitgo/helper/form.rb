require 'rack/utils'

module Gitgo
  module Helper
    class Form
      include Rack::Utils
      
      DEFAULT_STATES = %w{open closed}
      
      attr_reader :controller
      
      def initialize(controller)
        @controller = controller
      end
      
      def url(*paths)
        controller.url(paths)
      end
      
      #
      #
      #
      
      def value(str)
        str
      end
      
      #
      # documents
      #
      
      def at(sha)
        return '(unknown)' unless sha
        
        refs = refs.select {|ref| ref.commit.sha == sha }
        refs.collect! {|ref| escape_html ref.name }
        
        ref_names = refs.empty? ? nil : " (#{refs.join(', ')})"
        "#{sha_a(sha)}#{ref_names}"
      end
      
      def author_value(author)
        escape_html(author)
      end
      
      def title_value(title)
        escape_html(title)
      end
      
      def tags_value(tags)
        tags ? tags.join(', ') : ''
      end
      
      def content_value(content)
        content
      end
      
      def each_tag(tags, *selected) # :yields: value, select_or_check, content
        tags.sort.each do |tag|
          yield escape_html(tag), selected.include?(tag), escape_html(tag)
        end
      end
      
      def each_ref(refs, selected_name) # :yields: value, select_or_check, content
        refs.each do |ref|
          yield escape_html(ref.commit), selected_name == ref.name, escape_html(ref.name)
        end
      end
      
      def each_ref_name(refs, selected_name) # :yields: value, select_or_check, content
        found_selected_name = false
        
        refs.each do |ref|
          select_or_check = selected_name == ref.name
          found_selected_name = true if select_or_check
          
          yield escape_html(ref.name), select_or_check, escape_html(ref.name)
        end
        
        if found_selected_name
          yield("", false, "(none)")
        else
          yield(selected_name, true, selected_name.to_s.empty? ? "(none)" : selected_name)
        end
      end
    end
  end
end