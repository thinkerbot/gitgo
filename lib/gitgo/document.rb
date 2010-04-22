require 'gitgo/repo'
require 'gitgo/document/invalid_document_error'

module Gitgo
  
  # Document represents the data model of Gitgo, and provides high(er)-level
  # access to documents stored in a Repo.  Content and data consistency
  # constraints are enforced on Document.
  #
  class Document
    class << self
      
      # Returns a hash registry mapping a type string to a Document class.
      # Document itself is registered as the nil type.  Types also includes
      # reverse mappings for a Document class to it's type string.
      attr_reader :types
      
      # A hash of (key, validator) pairs mapping attribute keys to a
      # validation method.  Not all attributes will have a validator whereas
      # some attributes share the same validation method.
      attr_reader :validators
      
      def inherited(base) # :nodoc:
        base.instance_variable_set(:@validators, validators.dup)
        base.instance_variable_set(:@types, types)
        base.register_as base.to_s.split('::').last.downcase
      end
      
      # Returns the Repo currently in scope (see Repo.current)
      def repo
        Repo.current
      end
      
      # Returns the index on repo.
      def index
        repo.index
      end
      
      # Returns the type string for self.
      def type
        types[self]
      end
      
      # Creates a new document with the attributes and saves.  Note that a
      # saved document is not automatically associated with a graph in a
      # permanent way, nor will it be indexed.  Documents must be associated
      # with a graph via create/update/link to actually be 'stored' in the
      # repo, and reindexed manually using reindex.
      #
      # From a technical perspective, unstored documents are hanging blobs and
      # as such they will be gc'ed by git.
      def save(attrs={})
        new(attrs, repo).save
      end
      
      # Creates a new document with the attrs.  The document is saved, stored,
      # and indexed before being returned.  If parents are specified, the
      # document is linked to each of them rather than being stored.
      #
      # === Usage Note
      #
      # Use create in preference of save when you don't intend to link the
      # document to parents after creation (or when you know the parents and
      # can provide them to create).  Doing so results in fewer objects being
      # written the repo.
      #
      # For example, one correct way:
      #
      #   git = repo.git
      #
      #   a = Document.save(:content => 'a')
      #   b = Document.save(:content => 'b')
      #   a.create
      #   a.link(b)
      #
      #   git.status.length   # => 2
      #   git.reset
      #
      # Vs another correct way:
      #
      #   a = Document.create(:content => 'a')
      #   b = Document.create({:content => 'b'}, a)
      #
      #   git.status.length   # => 2
      #   git.reset
      #
      # Vs the wrong way:
      #
      #   a = Document.create(:content => 'a')
      #   b = Document.create(:content => 'b')
      #   a.link(b)
      #
      #   git.status.length   # => 3
      #
      # In the last case both a and b are stored as if they were graph heads,
      # and then b also gets used as a link.  The unnecessary storage of b as
      # a graph head results in an extra path in the repo (which actually
      # corresponds to 3 extra git objects; 2 trees and a blob).
      #
      def create(attrs={}, *parents)
        doc = save(attrs)
        
        if parents.empty?
          doc.create
        else
          parents.each do |parent|
            parent = Document[parent] unless parent.kind_of?(Document)
            parent.link(doc)
          end
        end
        
        doc.reindex
        doc
      end
      
      # Reads the specified document and casts it into an instance as per
      # cast.  Returns nil if the document doesn't exist.
      #
      # == Usage Note
      #
      # Read will re-read the document directly from the git repository every
      # time it is called.  For better performance, use the AGET method which
      # performs the same read but uses the Repo cache if possible.
      def read(sha)
        sha = repo.resolve(sha)
        attrs = repo.read(sha)
        
        attrs ? cast(attrs, sha) : nil
      end
      
      # Reads the specified document from the repo cache and casts it into an
      # instance as per cast.  Returns nil if the document doesn't exist.
      def [](sha)
        sha = repo.resolve(sha)
        cast(repo[sha], sha)
      end
      
      # Casts the attributes hash into a document instance.  The document
      # class is determined by resolving the 'type' attribute against the
      # types registry.
      def cast(attrs, sha)
        type = attrs['type']
        klass = types[type] or raise "unknown type: #{type}"
        klass.new(attrs, repo, sha)
      end
      
      # Updates and indexes the old document with new attributes.  The new
      # attributes are merged with the current doc attributes.  Returns the
      # new document.
      #
      # The new document can be used to update other documents, if necessary,
      # to resolve forks in the update graph:
      #
      #   a = Document.create(:content => 'a')
      #   b = Document.update(a, :content => 'b')
      #   c = Document.update(a, :content => 'c')
      #
      #   d = Document.update(b, :content => 'd')
      #   c.update(d)
      #
      #   a.reset
      #   a.node.versions.uniq    # => [d.sha]
      #
      def update(old_doc, attrs={})
        old_doc = Document[old_doc] unless old_doc.kind_of?(Document)
        
        new_doc = old_doc.merge(attrs).save
        old_doc.update(new_doc)
        new_doc.reindex
        new_doc
      end
      
      # Finds all documents matching the any and all criteria.  The any and
      # all inputs are hashes of index values used to filter all possible
      # documents. They consist of (key, value) or (key, [values]) pairs, at
      # least one of which must match in the any case, all of which must match
      # in the all case.  Specify nil for either array to prevent filtering
      # using that criteria.
      #
      # See basis for more detail regarding the scope of 'all documents' that
      # can be found via find.
      #
      # If update_index is specified, then the document index will be updated
      # before the find is performed.  Typically update_index should be
      # specified to true to capture any new documents added, for instance by
      # a merge; it adds little overhead in the most common case where the
      # index is already up-to-date.
      def find(all={}, any=nil, update_index=true)
        self.update_index if update_index
        index.select(
          :basis => basis, 
          :all => all, 
          :any => any, 
          :shas => true
        ).collect! {|sha| self[sha] }
      end
      
      # Performs a partial update of the document index.  All documents added
      # between the index-head and the repo-head are updated using this
      # method.
      #
      # Specify reindex to clobber and completely rebuild the index.
      def update_index(reindex=false)
        index.clear if reindex
        repo_head, index_head = repo.head, index.head
        
        # if the index is up-to-date save the work of doing diff
        if repo_head.nil? || repo_head == index_head
          return []
        end
        
        shas = repo.diff(index_head, repo_head)
        shas.each {|sha| self[sha].reindex }
        
        index.write(repo.head)
        shas
      end
      
      protected
      
      # Returns the basis for finds, ie the set of documents that get filtered
      # by the find method.  
      #
      # If type is specified for self, then only documents of type will be
      # available (ie Issue.find will only find documents of type 'issue'). 
      # Document itself will filter all documents with an email; which should
      # typically represent all possible documents.
      def basis
        type ? index['type'][type] : index.all('email')
      end
      
      # Registers self as the specified type.  The previous registered type is
      # overridden.
      def register_as(type)
        types.delete_if {|key, value| key == self || value == self }
        types[type] = self
        types[self] = type
      end
      
      # Turns on attribute definition for the duration of the block.  If
      # attribute definition is on, then the standard attribute declarations
      # (attr_reader, attr_writer, attr_accessor) will create accessors for
      # the attrs hash rather than instance variables.
      #
      # Moreover, blocks given to attr_writer/attr_accessor will be used to
      # define a validator for the accessor.
      def define_attributes(&block)
        begin
          @define_attributes = true
          instance_eval(&block)
        ensure
          @define_attributes = false
        end
      end
      
      def attr_reader(*keys) # :nodoc:
        return super unless @define_attributes
        keys.each do |key|
          key = key.to_s
          define_method(key) { attrs[key] }
        end
      end
      
      def attr_writer(*keys, &block) # :nodoc:
        return super unless @define_attributes
        keys.each do |key|
          key = key.to_s
          define_method("#{key}=") {|value| attrs[key] = value }
          validate(key, &block) if block_given?
        end
      end
      
      def attr_accessor(*keys, &block) # :nodoc:
        return super unless @define_attributes
        attr_reader(*keys)
        attr_writer(*keys, &block)
      end
      
      # Registers the validator method to validate the specified attribute. If
      # a block is given, it will be used to define the validator as a
      # protected instance method (otherwise you need to define the validator
      # method manually).
      def validate(key, validator="validate_#{key}", &block)
        validators[key.to_s] = validator.to_sym
        
        if block_given?
          define_method(validator, &block)
          protected validator
        end
      end
    end
    
    AUTHOR = /\A.*?<.*?>\z/
    DATE = /\A\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d-\d\d:\d\d\z/
    SHA = Git::SHA
    
    @define_attributes = false
    @validators = {}
    @types = {}
    register_as(nil)
    
    # The repo this document belongs to.
    attr_reader :repo
    
    # A hash of the document attributes, corresponding to what is stored in
    # the repo.
    attr_reader :attrs
    
    # The document sha, unset until the document is saved.
    attr_reader :sha
    
    validate(:author) {|author| validate_format(author, AUTHOR) }
    validate(:date)   {|date|   validate_format(date, DATE) }

    define_attributes do
      attr_accessor(:at)   {|at|   validate_format_or_nil(at, SHA) }
      attr_writer(:tags)   {|tags| validate_array_or_nil(tags) }
      attr_accessor(:type)
    end
    
    def initialize(attrs={}, repo=nil, sha=nil)
      @repo = repo || Repo.current
      @attrs = attrs
      reset(sha)
    end
    
    # Returns the repo index.
    def index
      repo.index
    end
    
    def idx
      sha ? index.idx(sha) : nil
    end
    
    def graph_head_idx
      index.graph_head_idx(idx)
    end
    
    def graph_head?
      graph_head_idx == idx
    end
    
    def graph_head
      idx = graph_head_idx
      idx ? index.list[idx] : nil
    end
    
    def graph
      @graph ||= repo.graph(graph_head)
    end
    
    def node
      graph[sha]
    end
    
    # Gets the specified attribute.
    def [](key)
      attrs[key]
    end
    
    # Sets the specified attribute.
    def []=(key, value)
      attrs[key] = value
    end
    
    def author=(author)
      if author.kind_of?(Grit::Actor)
        author = author.email ? "#{author.name} <#{author.email}>" : author.name
      end
      self['author'] = author
    end
    
    def author(cast=true)
      author = attrs['author']
      if cast && author.kind_of?(String)
        author = Grit::Actor.from_string(author)
      end
      author
    end
    
    def date=(date)
      if date.respond_to?(:iso8601)
        date = date.iso8601
      end
      self['date'] = date
    end
    
    def date(cast=true)
      date = attrs['date']
      if cast && date.kind_of?(String)
        date = Time.parse(date)
      end
      date
    end
    
    def active?(commit=nil)
      return true if at.nil? || commit.nil?
      repo.rev_list(commit).include?(at)
    end
    
    def tags
      self['tags'] ||= []
    end
    
    def merge(attrs)
      dup.merge!(attrs)
    end
    
    def merge!(attrs)
      self.attrs.merge!(attrs)
      self
    end
    
    def normalize
      dup.normalize!
    end
    
    def normalize!
      attrs['author'] ||= begin
        author = repo.author
        "#{author.name} <#{author.email}>"
      end
      
      attrs['date'] ||= Time.now.iso8601
      
      if at = attrs['at']
        attrs['at'] = repo.resolve(at)
      end
      
      if tags = attrs['tags']
        attrs['tags'] = arrayify(tags)
      end
      
      unless type = attrs['type']
        default_type = self.class.type
        attrs['type'] = default_type if default_type
      end
      
      self
    end
    
    def errors
      errors = {}
      self.class.validators.each_pair do |key, validator|
        begin
          send(validator, attrs[key])
        rescue
          errors[key] = $!
        end
      end
      errors
    end
    
    def validate(normalize=true)
      normalize! if normalize
      
      errors = self.errors
      unless errors.empty?
        raise InvalidDocumentError.new(self, errors)
      end
      self
    end
    
    def indexes
      indexes = []
      each_index {|key, value| indexes << [key, value] }
      indexes
    end
    
    def each_index
      if author = attrs['author']
        actor = Grit::Actor.from_string(author)
        yield('email', blank?(actor.email) ? 'unknown' : actor.email)
      end
      
      if date = attrs['date']
        # reformats iso8601 as YYYYMMDD
        yield('date', "#{date[0,4]}#{date[5,2]}#{date[8,2]}")
      end
      
      if at = attrs['at']
        yield('at', at)
      end
      
      if tags = attrs['tags']
        tags.each do |tag|
          yield('tags', tag)
        end
      end
      
      if type = attrs['type']
        yield('type', type)
      end
      
      self
    end
    
    def save
      validate
      reset repo.store(attrs)
    end
    
    def saved?
      sha.nil? ? false : true
    end
    
    def create
      unless saved?
        raise "cannot create unless saved"
      end
      
      repo.create(sha)
      self
    end
    
    def update(new_sha)
      unless saved?
        raise "cannot update unless saved"
      end
      
      if new_sha.kind_of?(Document)
        unless new_sha.saved?
          raise "cannot update with an unsaved document: #{new_sha.inspect}" 
        end
        new_sha.reset
        new_sha = new_sha.sha
      end
      
      repo.update(sha, new_sha)
      reset
    end
    
    def link(*children)
      unless saved?
        raise "cannot link unless saved"
      end
      
      children.collect! do |child|
        next child unless child.kind_of?(Document)
        
        unless child.saved?
          raise "cannot link to an unsaved document: #{child.inspect}"
        end
        child.reset
        child.sha
      end
      
      children.each do |child|
        repo.link(sha, child)
      end
      reset
    end
    
    def reindex
      raise "cannot reindex unless saved" unless saved?
      
      idx = self.idx
      each_index do |key, value|
        index[key][value] << idx
      end
      
      self
    end
    
    def reset(new_sha=sha)
      @sha = new_sha
      @graph = nil
      self
    end
    
    def commit!
      repo.commit!
      self
    end
    
    def initialize_copy(orig)
      super
      reset(nil)
      @attrs = orig.attrs.dup
    end
    
    def inspect
      "#<#{self.class}:#{object_id} sha=#{sha.inspect}>"
    end
    
    # This is a thin equality -- use with caution.
    def ==(another)
      saved? && another.kind_of?(Document) ? sha == another.sha : super
    end
    
    protected
    
    def arrayify(obj)
      case obj
      when Array  then obj
      when nil    then []
      when String then obj.strip.empty? ? [] : [obj]
      else [obj]
      end
    end
    
    def blank?(obj)
      obj.nil? || obj.to_s.strip.empty?
    end
    
    def validate_not_blank(str)
      if blank?(str)
        raise 'nothing specified'
      end
    end
    
    def validate_format(value, format)
      if value.nil?
        raise 'missing'
      end
      
      unless value =~ format
        raise 'misformatted'
      end
    end
    
    def validate_format_or_nil(value, format)
      value.nil? || validate_format(value, format)
    end
    
    def validate_array_or_nil(value)
      unless value.nil? || value.kind_of?(Array)
        raise 'not an array'
      end
    end
  end
end