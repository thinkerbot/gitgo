require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/document'

class DocumentTest < Test::Unit::TestCase
  acts_as_file_test
  
  Repo = Gitgo::Repo
  Document = Gitgo::Document
  InvalidDocumentError = Document::InvalidDocumentError
  
  attr_accessor :author, :doc
  
  def setup
    super
    
    @author = Grit::Actor.new("John Doe", "john.doe@email.com")
    @current = Repo.set_env(Repo::PATH => method_root.path(:repo), Repo::OPTIONS => {:author => author})
    @doc = Document.new
  end
  
  def teardown
    Repo.set_env(@current)
    super
  end
  
  def repo
    Repo.current
  end
  
  def git
    repo.git
  end
  
  def idx
    repo.idx
  end
  
  def deserialize(str)
    JSON.parse(str)
  end
  
  def date_path(date, sha)
    Repo::Utils.date_path(date, sha)
  end
  
  #
  # Document.validators test
  #

  class ValidatorA < Document
    validate(:a, :validator)
    validate(:b)
    
    def validator(value)
      raise("got: #{value}")
    end
  end
  
  def test_validate_binds_validator_to_method_name
    assert_equal :validator, ValidatorA.validators['a']
  end
  
  def test_validate_infers_default_validator_name
    assert_equal :validate_b, ValidatorA.validators['b']
  end
  
  def test_validator_is_called_with_attrs_value_to_determine_errors
    a = ValidatorA.new 'a' => 'value'
    assert_equal 'got: value', a.errors['a'].message
  end
  
  class ValidatorB < ValidatorA
    validate(:c, :validator)
  end
  
  def test_validators_are_inherited_down_but_not_up
    a = ValidatorA.new 'a' => 'A', 'c' => 'C'
    assert_equal 'got: A', a.errors['a'].message
    assert_equal nil, a.errors['c']
    
    b = ValidatorB.new 'a' => 'A', 'c' => 'C'
    assert_equal 'got: A', b.errors['a'].message
    assert_equal 'got: C', b.errors['c'].message
  end
  
  #
  # Document.define_attributes test
  #
  
  class DefineAttributesA < Document
    define_attributes do
      attr_reader :reader
      attr_writer :writer
      attr_accessor :accessor
    end
  end
  
  def test_define_attributes_causes_attr_x_methods_to_read_and_write_attrs
    a = DefineAttributesA.new

    assert_equal true, a.respond_to?(:reader)
    assert_equal false, a.respond_to?(:reader=)
    assert_equal false, a.respond_to?(:writer)
    assert_equal true, a.respond_to?(:writer=)
    assert_equal true, a.respond_to?(:accessor)
    assert_equal true, a.respond_to?(:accessor=)
    
    a.attrs['reader'] = 'one'
    assert_equal 'one', a.reader
    
    a.writer = 'two'
    assert_equal 'two', a.attrs['writer']
    
    a.accessor = 'three'
    assert_equal 'three', a.attrs['accessor']
    
    a.attrs['accessor'] = 'four'
    assert_equal 'four', a.accessor
  end
  
  class DefineAttributesB < Document
    define_attributes do
      attr_reader :not_validated
      attr_writer(:validated) {|value| raise('msg') if value.nil? }
      attr_accessor(:also_validated) {|value| raise('msg') if value.nil? }
    end
  end
  
  def test_define_attributes_causes_attr_writer_to_create_validator_from_block
    assert_equal nil, DefineAttributesB.validators['not_validated']
    assert_equal :validate_validated, DefineAttributesB.validators['validated']
    assert_equal :validate_also_validated, DefineAttributesB.validators['also_validated']
  end
  
  #
  # Document.register_as test
  #
  
  class RegisterClass < Document
    register_as 'type'
  end
  
  def test_register_as_registers_class_to_type
    assert_equal RegisterClass, Document.types['type']
  end
  
  def test_types_are_shared_among_all_documents
    assert_equal Document.types.object_id, RegisterClass.types.object_id
  end
  
  class AutoRegisterClass < Document
  end
  
  def test_subclasses_are_automatically_registered_by_downcased_const_name
    assert_equal AutoRegisterClass, Document.types['autoregisterclass']
  end
  
  #
  # Document.create test
  #
  
  def test_create_initializes_doc_and_saves
    a = Document.create('content' => 'a')
    assert_equal true, a.saved?
    
    attrs = deserialize(git.get(:blob, a.sha).data)
    assert_equal 'a', attrs['content']
  end
  
  def test_create_caches_document_attrs
    assert_equal({}, repo.cache)

    a = Document.create('content' => 'a')
    assert_equal({a.sha => a.attrs}, repo.cache)
  end
  
  #
  # Document.read test
  #
  
  def test_read_reads_document
    doc['content'] = 'a'
    doc.save
    
    assert_equal 'a', Document.read(doc.sha)['content']
  end
  
  class ReadClass < Document
    register_as 'read_type'
  end
  
  def test_read_casts_document_to_registered_type
    doc.type = 'read_type'
    doc.save
    
    result = Document.read(doc.sha)
    assert_equal ReadClass, result.class
  end
  
  #
  # Document.update test
  #
  
  def test_update_merges_attrs_saves_and_returns_new_doc
    a = Document.create('content' => 'a', 'tags' => 'one')
    b = Document.update(a.sha, 'content' => 'b')
    
    assert_equal 'a', a['content']
    assert_equal 'b', b['content']
    assert_equal ['one'], b['tags']
  end
  
  def test_update_indexes_document
    a = Document.create
    b = Document.update(a.sha, 'tags' => 'tag')
    assert_equal [b.sha], idx['tags']['tag']
  end
  
  #
  # Document.find test
  #
  
  def test_find_returns_documents_matching_criteria
    a = Document.create('content' => 'a', 'tags' => ['one'])
    b = Document.create('content' => 'b', 'tags' => ['one', 'two'])
    c = Document.create('content' => 'c', 'tags' => ['two'])
    
    results = Document.find.collect {|doc| doc['content'] }
    assert_equal ['a', 'b', 'c'], results
    
    results = Document.find('tags' => 'one').collect {|doc| doc['content'] }
    assert_equal ['a', 'b'], results
    
    results = Document.find('tags' => 'three').collect {|doc| doc['content'] }
    assert_equal [], results
    
    results = Document.find('tags' => ['one', 'two']).collect {|doc| doc['content'] }
    assert_equal ['b'], results
  end
  
  def test_find_caches_documents
    a = Document.create('content' => 'a', 'tags' => ['one'])
    
    results = Document.find.collect {|doc| doc['content'] }
    assert_equal ['a'], results
    assert_equal({a.sha => a.attrs}, repo.cache)
  end
  
  class FindDoc < Document
  end
  
  def test_find_filters_by_type_if_specified
    a = Document.create('content' => 'a')
    b = FindDoc.create('content' => 'b')
    c = FindDoc.create('content' => 'c')
    
    results = Document.find.collect {|doc| doc['content'] }
    assert_equal ['a', 'b', 'c'], results
    
    results = FindDoc.find.collect {|doc| doc['content'] }
    assert_equal ['b', 'c'], results
  end
  
  #
  # update_idx test
  #
  
  def test_update_idx_indexes_docs_between_index_head_to_repo_head
    a = Document.create({'content' => 'a', 'tags' => ['one']}).sha
    one = repo.commit
    
    b = Document.create({'content' => 'c', 'tags' => ['one']}).sha
    two = repo.commit
    
    c = Document.create({'content' => 'b', 'tags' => ['one']}).sha
    three = repo.commit
    
    idx.clear
    Document.update_idx
    assert_equal [a, b, c].sort, idx['tags']['one'].sort
    
    idx.clear
    idx.write(one)
    Document.update_idx
    assert_equal [b, c].sort, idx['tags']['one'].sort
    
    idx.clear
    idx.write(one)
    git.checkout(two)
    Document.update_idx
    assert_equal [b].sort, idx['tags']['one'].sort
  end
  
  def test_update_idx_updates_index_head_to_repo_head
    Document.create
    idx.clear
    
    assert_equal nil, idx.head
    Document.update_idx
    assert_equal repo.head, idx.head
  end
  
  def test_update_idx_does_not_update_index_head_if_repo_head_is_nil
    assert_equal nil, idx.head
    Document.update_idx
    assert_equal nil, idx.head
  end
  
  def test_update_idx_clears_existing_index_if_specified
    idx.set('key', 'value', 'sha')
    
    assert_equal ['sha'], idx.get('key', 'value')
    Document.update_idx(true)
    assert_equal [], idx.get('key', 'value')
  end
  
  def test_update_caches_doc_attrs
    assert_equal({}, repo.cache)

    a = Document.create('content' => 'a')
    b = Document.update(a.sha, 'content' => 'b')
    assert_equal({a.sha => a.attrs, b.sha => b.attrs}, repo.cache)
  end
  
  #
  # Document[] test
  #
  
  def test_Document_AGET_reads_attrs_from_cache_and_casts_to_document
    a = Document.create('content' => 'a')
    b = Document[a.sha]
    
    assert_equal 'a', b['content']
    assert_equal({a.sha => b.attrs}, repo.cache)
  end
  
  #
  # initialize test
  #
  
  def test_initialize_does_not_parse_attributes
    doc = Document.new('author' => 'Jane Doe <jane.doe@email.com>')
    assert_equal({'author' => 'Jane Doe <jane.doe@email.com>'}, doc.attrs)
  end
  
  def test_initialize_uses_current_repo_unless_specified
    doc = Document.new
    assert_equal Repo.current, doc.repo
  end
  
  #
  # author= test
  #
  
  def test_set_author_stringifies_actors
    doc.author = author
    assert_equal 'John Doe <john.doe@email.com>', doc.attrs['author']
  end
  
  #
  # author test
  #
  
  def test_author_casts_string_author_to_actor_if_cast_is_specified
    doc.attrs['author'] = 'Jane Doe <jane.doe@email.com>'
    assert_equal Grit::Actor, doc.author.class
    assert_equal String, doc.author(false).class
  end
  
  def test_author_does_not_attempt_to_cast_nil_authors
    doc.attrs['author'] = nil
    assert_equal nil, doc.author
    assert_equal nil, doc.author(false)
  end
  
  #
  # date= test
  #
  
  def test_set_date_converts_inputs_using_iso8601_if_possible
    date = Time.now
    doc.date = date
    assert_equal date.iso8601, doc.attrs['date']
  end
  
  #
  # date test
  #
  
  def test_date_casts_string_date_to_Time_if_cast_is_specified
    doc.attrs['date'] = Time.now.iso8601
    assert_equal Time, doc.date.class
    assert_equal String, doc.date(false).class
  end
  
  def test_date_does_not_attempt_to_cast_nil_dates
    doc.attrs['date'] = nil
    assert_equal nil, doc.date
    assert_equal nil, doc.date(false)
  end
  
  #
  # AGET test
  #
  
  def test_AGET_gets_attribute_from_attrs
    doc = Document.new
    doc.attrs['author'] = 'Jane Doe <jane.doe@email.com>'
    assert_equal 'Jane Doe <jane.doe@email.com>', doc['author']
  end
  
  #
  # ASET test
  #
  
  def test_ASET_sets_attribute_into_attrs
    doc = Document.new
    doc['author'] = 'Jane Doe <jane.doe@email.com>'
    assert_equal 'Jane Doe <jane.doe@email.com>', doc.attrs['author']
  end
  
  #
  # origin test
  #
  
  def test_origin_returns_re
    doc.re = :re
    assert_equal :re, doc.origin 
  end
  
  def test_origin_returns_sha_if_re_is_not_specified
    sha = git.set(:blob, '')
    
    assert_equal nil, doc.origin
    doc.sha = sha
    assert_equal sha, doc.origin
  end
  
  #
  # origin? test
  #
  
  def test_origin_check_returns_true_if_re_is_nil
    assert_equal true, doc.origin?
    doc.re = :re
    assert_equal false, doc.origin?
  end
  
  #
  # active? test
  #
  
  def test_active_returns_true_if_at_is_in_rev_list_for_commit
    git['one'] = 'A'
    one = git.commit("added one")
    
    git['two'] = 'B'
    two = git.commit("added two")
    
    doc.at = one
    assert_equal true, doc.active?(one)
    assert_equal true, doc.active?(two)
    
    doc.at = two
    assert_equal false, doc.active?(one)
    assert_equal true, doc.active?(two)
  end
  
  def test_active_returns_true_if_commit_is_nil
    assert_equal true, doc.active?(nil)
  end
  
  def test_active_returns_true_if_at_is_not_set
    git['one'] = 'A'
    one = git.commit("added one")
    
    assert_equal true, doc.active?(one)
  end
  
  #
  # tail? test
  #
  
  def test_tail_check_returns_true_unless_saved
    assert_equal false, doc.saved?
    assert_equal true, doc.tail?
  end
  
  def test_tail_check_returns_false_unless_doc_is_tail_and_current
    doc['content'] = 'a'
    doc.save
    assert_equal true, doc.tail?
    
    # update
    dup = doc.dup
    dup['content'] = 'b'
    update_sha = dup.update(doc.sha)
    assert_equal true, dup.tail?
    assert_equal false, doc.tail?
    
    # child
    child = Document.new('content' => 'c', 're' => doc.sha, 'parents' => [dup.sha]).save
    assert_equal false, dup.tail?
  end
  
  #
  # parents test
  #
  
  def test_parents_returns_parents_in_attrs_if_set
    assert_equal [], doc.parents
    doc['parents'] = ['parent']
    assert_equal ['parent'], doc.parents
  end
  
  def test_parents_queries_graph_for_parents_if_parents_are_not_set_and_doc_is_saved
    a = repo.store
    doc.origin = a
    doc.parents = [a]
    doc.save
    
    doc.parents = nil
    assert_equal [a], doc.parents
  end
  
  #
  # children test
  #
  
  def test_children_returns_children_in_attrs_if_set
    assert_equal [], doc.children
    doc['children'] = ['child']
    assert_equal ['child'], doc.children
  end
  
  def test_children_queries_graph_for_children_if_children_are_not_set_and_doc_is_saved
    a = repo.store
    b = repo.store('re' => a)
    doc.children = [b]
    doc.re = a
    doc.save
    
    doc.children = nil
    assert_equal [b], doc.children
  end
  
  #
  # merge test
  #
  
  def test_merge_duplicates_and_merge_bangs_attrs
    doc.attrs['one'] = 'one'
    doc.attrs['two'] = 'two'
    dup = doc.merge('two' => 'TWO', 'three' => 'THREE')
    
    assert_equal({'one' => 'one', 'two' => 'two'}, doc.attrs)
    assert_equal({'one' => 'one', 'two' => 'TWO', 'three' => 'THREE'}, dup.attrs)
  end
  
  #
  # merge! test
  #
  
  def test_merge_bang_merges_new_attrs_with_existing
    doc.attrs['one'] = 'one'
    doc.attrs['two'] = 'two'
    doc.merge!('two' => 'TWO', 'three' => 'THREE')
    
    assert_equal({'one' => 'one', 'two' => 'TWO', 'three' => 'THREE'}, doc.attrs)
  end
  
  #
  # errors test
  #
  
  class ErrorDoc < Document
    validate(:must_be_specifed) {|value| raise("not specified") if value.nil? }
  end
  
  def test_errors_detects_missing_attrs
    doc = ErrorDoc.new
    assert_equal nil, doc['must_be_specifed']
    assert_equal 'not specified', doc.errors['must_be_specifed'].message
  end
  
  def test_errors_detects_missing_author
    doc.author = nil
    assert_equal 'missing', doc.errors['author'].message
  end
  
  def test_errors_detects_misformatted_author
    doc.author = 'No Email'
    assert_equal 'misformatted', doc.errors['author'].message
  end
  
  def test_errors_detects_missing_date
    doc.date = nil
    assert_equal 'missing', doc.errors['date'].message
  end
  
  def test_errors_detects_misformatted_date
    doc.date = '12345'
    assert_equal 'misformatted', doc.errors['date'].message
  end
  
  def test_errors_detects_non_sha_re
    doc.re = 'notasha'
    assert_equal 'misformatted', doc.errors['re'].message
  end
  
  def test_errors_detects_non_sha_at
    doc.at = 'notasha'
    assert_equal 'misformatted', doc.errors['at'].message
  end
  
  def test_errors_detects_non_array_parents
    doc.parents = 'parent'
    assert_equal 'not an array', doc.errors['parents'].message
  end
  
  def test_errors_detects_parents_with_different_origins
    a = repo.store('content' => 'a')
    b = repo.store('content' => 'b', 're' => a)
    c = repo.store('content' => 'c')
    
    doc.parents = [b]
    assert_equal 'parent and child have different origins', doc.errors['parents'].message
    
    doc.re = c
    assert_equal 'parent and child have different origins', doc.errors['parents'].message
    
    doc.re = a
    assert_equal nil, doc.errors['parents']
  end
  
  def test_errors_detects_non_array_children
    doc.children = 'child'
    assert_equal 'not an array', doc.errors['children'].message
  end
  
  def test_errors_detects_children_with_different_origins
    a = repo.store('content' => 'a')
    b = repo.store('content' => 'b', 're' => a)
    c = repo.store('content' => 'c')

    doc.children = [b]
    assert_equal 'parent and child have different origins', doc.errors['children'].message
    
    doc.re = c
    assert_equal 'parent and child have different origins', doc.errors['children'].message
    
    doc.re = a
    assert_equal nil, doc.errors['children']
  end
  
  def test_errors_detects_non_array_tags
    doc.tags = 'tag'
    assert_equal 'not an array', doc.errors['tags'].message
  end
  
  #
  # normalize test
  #
  
  def test_normalize_returns_duplicate_that_has_been_normalized
    doc['key'] = 'value'
    norm = doc.normalize
    
    assert_equal nil, doc.author
    assert_equal author.email, norm.author.email
    assert_equal 'value', norm['key']
  end
  
  #
  # normalize! test
  #
  
  def test_normalize_bang_sets_author_using_repo_author_if_unset
    assert_equal nil, doc.author
    doc.normalize!
    assert_equal author.email, doc.author.email
  end
  
  def test_normalize_bang_sets_date_if_unset
    assert_equal nil, doc.date
    doc.normalize!
    assert_in_delta Time.now.to_f, doc.date.to_f, 1
  end
  
  def test_normalize_bang_resolves_re_if_set
    a = repo.store
    doc.re = a[0, 8]
    doc.normalize!
    assert_equal a, doc.re
  end
  
  def test_normalize_bang_resolves_at_if_set
    a = git['a'] = 'content'
    git.commit('added blob')
    
    doc.at = a[0, 8]
    doc.normalize!
    assert_equal a, doc.at
  end
  
  def test_normalize_bang_arrayifies_parents
    a = repo.store
    doc.parents = a
    doc.normalize!
    assert_equal [a], doc.parents
  end
  
  def test_normalize_bang_resolves_parents
    a = git['a'] = 'content'
    git.commit('added blob')
    
    doc.parents = [a[0,8], a[0,8]]
    doc.normalize!
    assert_equal [a, a], doc.parents
  end
  
  def test_normalize_bang_arrayifies_children
    a = repo.store
    doc.children = a
    doc.normalize!
    assert_equal [a], doc.children
  end
  
  def test_normalize_bang_resolves_children
    a = git['a'] = 'content'
    git.commit('added blob')
    
    doc.children = [a[0,8], a[0,8]]
    doc.normalize!
    assert_equal [a, a], doc.children
  end
  
  def test_normalize_bang_arrayifies_tags
    doc.tags = 'tag'
    doc.normalize!
    assert_equal ['tag'], doc.tags
  end
  
  class RegisterDoc < Document
    register_as 'reg_doc'
  end
  
  def test_normalize_bang_sets_type_registered_to_class
    doc = RegisterDoc.new
    doc.normalize!
    assert_equal 'reg_doc', doc.type
  end
  
  def test_normalize_bang_does_not_set_type_if_class_is_not_registered
    assert_equal nil, Document.type
    
    doc.normalize!
    assert_equal nil, doc.type
    assert_equal false, doc.attrs.has_key?('type')
  end
  
  #
  # save test
  #
  
  def test_save_stores_attrs_and_sets_sha
    doc['key'] = 'value'
    doc.save
    
    attrs = repo.read(doc.sha)
    assert_equal 'value', attrs['key']
  end
  
  def test_save_links_to_parents_to_doc
    a = repo.store('content' => 'a')
    doc['parents'] = [a]
    doc['re'] = a
    doc.save
    
    assert_equal [doc.sha], repo.links(a)
  end
  
  def test_save_links_doc_to_children
    a = repo.store('content' => 'a')
    b = repo.store('content' => 'b', 're' => a)
    doc['children'] = [b]
    doc['re'] = a
    doc.save
    
    assert_equal [b], repo.links(doc.sha)
  end
  
  def test_save_indexes_doc
    doc['tags'] = 'one'
    doc.save
    
    assert_equal [doc.sha], idx['tags']['one']
  end
  
  def test_save_stores_according_to_present_date
    doc['date'] = Time.at(100).iso8601
    sha = doc.save
    
    assert_equal git.get(:blob, sha).data, git[date_path(Time.now, sha)]
  end
  
  def test_multiple_sequential_saves_returns_same_sha
    a = doc.save
    b = doc.save
    
    assert_equal a, b
  end
  
  def test_re_saving_a_saved_document_does_not_store_document_twice
    doc.validate
    sha = repo.store(doc.attrs, Time.at(100))
    doc.sha = sha
    
    assert_equal sha, doc.save
    assert_equal git.get(:blob, sha).data, git[date_path(Time.at(100), sha)]
    assert_equal nil, git[date_path(Time.now, sha)]
  end
  
  def test_forcing_save_stores_a_document_twice
    doc.validate
    sha = repo.store(doc.attrs, Time.at(100))
    doc.sha = sha
    
    assert_equal sha, doc.save(true)
    assert_equal git.get(:blob, sha).data, git[date_path(Time.at(100), sha)]
    assert_equal git.get(:blob, sha).data, git[date_path(Time.now, sha)]
  end

  class SaveDoc < Document
    validate(:key) {|key| raise("no key") if key.nil? }
  end
  
  def test_save_validates_doc
    doc = SaveDoc.new
    err = assert_raises(InvalidDocumentError) { doc.save }
    assert_equal "no key", err.errors['key'].message
    assert_equal nil, doc.sha
    
    doc['key'] = 'value'
    doc.save
    attrs = repo.read(doc.sha)
    assert_equal 'value', attrs['key']
  end
  
  class NormDoc < Document
    validate(:key) {|key| raise("nil key") if key.nil? }
    
    def normalize!
      super
      attrs['key'] = 'value' unless attrs.has_key?('key')
    end
  end
  
  def test_save_normalizes_doc_before_validate
    doc = NormDoc.new
    doc.save
    assert_equal 'value', doc['key']
    
    doc = NormDoc.new 'key' => nil
    err = assert_raises(InvalidDocumentError) { doc.save }
    assert_equal "nil key", err.errors['key'].message
  end
  
  #
  # saved? test
  #
  
  def test_saved_check_returns_true_if_sha_is_set
    assert_equal nil, doc.sha
    assert_equal false, doc.saved?
    
    doc.sha = :sha
    assert_equal true, doc.saved?
  end
  
  #
  # update test
  #
  
  def test_update_saves_and_updates_old_sha_with_self
    a = Document.new('content' => 'a').save
    b = Document.new('content' => 'b').update(a)
    
    attrs = deserialize(git.get(:blob, b).data)
    assert_equal 'b', attrs['content']
    assert_equal [b], repo.updates(a)
    assert_equal true, repo.updated?(a)
  end
  
  def test_update_is_equivalent_to_save_if_old_sha_is_nil
    a = Document.new('content' => 'a').update(nil)
    assert_equal false, repo.updated?(a)
  end
  
  def test_update_updates_self_sha_by_default
    doc['content'] = 'a'
    a = doc.save
    
    doc['content'] = 'b'
    b = doc.update
    
    attrs = deserialize(git.get(:blob, b).data)
    assert_equal 'b', attrs['content']
    assert_equal [b], repo.updates(a)
    assert_equal true, repo.updated?(a)
  end
  
  def test_multiple_sequential_updates_returns_same_sha
    a = doc.update
    b = doc.update
    
    assert_equal a, b
  end
  
  def test_updating_a_document_always_stores_the_document
    doc.validate
    sha = repo.store(doc.attrs, Time.at(100))
    doc.sha = sha
    
    assert_equal sha, doc.update
    assert_equal git.get(:blob, sha).data, git[date_path(Time.at(100), sha)]
    assert_equal git.get(:blob, sha).data, git[date_path(Time.now, sha)]
  end
  
  #
  # indexes test
  #

  def test_indexes_includes_author_email
    doc['author'] = 'Jane Doe <jane.doe@email.com>'
    assert_equal [['email', 'jane.doe@email.com']], doc.indexes
  end
  
  def test_indexes_uses_unknown_as_author_email_if_no_email_is_provided
    doc['author'] = 'Jane Doe <>'
    assert_equal [['email', 'unknown']], doc.indexes
    
    doc['author'] = 'Jane Doe < >'
    assert_equal [['email', 'unknown']], doc.indexes
    
    doc['author'] = 'Jane Doe'
    assert_equal [['email', 'unknown']], doc.indexes
  end
  
  def test_indexes_includes_each_tag_individually
    doc['tags'] = ['one', 'two']
    
    assert_equal [
      ['tags', 'one'],
      ['tags', 'two']
    ], doc.indexes
  end
  
  def test_indexes_includes_at
    doc['at'] = 'sha'
    assert_equal [['at', 'sha']], doc.indexes
  end
  
  def test_indexes_includes_re
    doc['re'] = 'sha'
    assert_equal [['re', 'sha']], doc.indexes
  end
  
  def test_indexes_includes_type
    doc['type'] = 'doc'
    assert_equal [['type', 'doc']], doc.indexes
  end
  
  def test_indexes_includes_tail_filter_if_saved_and_not_tail
    doc['content'] = 'parent'
    parent = doc.save
    
    child = doc.dup
    child.parents = [parent]
    child['re'] = parent
    child['content'] = 'child'
    child.save
    
    assert_equal false, doc.tail?
    assert_equal [['email', 'john.doe@email.com'], ['tail', 'filter']], doc.indexes
    
    assert_equal true, child.tail?
    assert_equal [['email', 'john.doe@email.com'], ['re', parent]], child.indexes
  end
  
  #
  # each_index test
  #
  
  def test_each_index_yields_index_pairs_to_block
    doc['author'] = 'Jane Doe <jane.doe@email.com>'
    
    pairs = []
    doc.each_index {|key, value| pairs << [key, value]}
    assert_equal [['email', 'jane.doe@email.com']], pairs
  end
end