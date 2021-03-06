require File.dirname(__FILE__) + "/../../test_helper"
require 'gitgo/documents/issue'

class IssueTest < Test::Unit::TestCase
  acts_as_file_test
  
  Repo = Gitgo::Repo
  Issue = Gitgo::Documents::Issue
  
  attr_accessor :issue
  
  def setup
    super
    @current = Repo.set_env(Repo::PATH => method_root.path(:repo))
    @issue = Issue.new
  end
  
  def teardown
    Repo.set_env(@current)
    super
  end
  
  #
  # find test
  #
  
  def test_find_searches_issues_by_tails
    a = Issue.create('tags' => 'open')
    b = Issue.save('tags' => 'closed')
    a.link(b)
    
    assert_equal [a], Issue.find('tags' => 'closed')
    
    c = Issue.create('tags' => 'open')
    b.link(c)
    
    assert_equal [], Issue.find('tags' => 'closed')
  end
  
  def test_find_does_not_return_duplicate_issues_for_multiple_matching_tails
    a = Issue.create('tags' => 'open')
    b = Issue.save('tags' => 'closed')
    a.link(b)
    
    c = Issue.save('tags' => 'closed')
    a.link(c)
    
    assert_equal [a], Issue.find(nil, 'tags' => 'closed')
  end
  
  #
  # graph_heads test
  #
  
  def test_graph_heads_returns_current_versions_of_graph_head
    a = Issue.create('title' => 'a', 'tags' => 'open')
    b = Issue.update(a, 'title' => 'b')
    c = Issue.update(a, 'title' => 'c')
    d = Issue.save('title' => 'd', 'tags' => 'open')
    b.link(d)
    
    a.reset
    assert_equal ['b', 'c'], a.graph_heads.collect {|head| head.title }.sort
    
    d.reset
    assert_equal ['b', 'c'], d.graph_heads.collect {|head| head.title }.sort
  end
  
  #
  # graph_tails test
  #
  
  def test_graph_tails_returns_all_graph_tails
    a = Issue.create('title' => 'a', 'tags' => 'open')
    b = Issue.save('title' => 'b', 'tags' => 'open')
    a.link(b)
    
    c = Issue.update(b, 'title' => 'c')
    d = Issue.save('title' => 'd', 'tags' => 'open')
    a.link(d)
    
    a.reset
    assert_equal ['c', 'd'], a.graph_tails.collect {|tail| tail.title }.sort
    
    d.reset
    assert_equal ['c', 'd'], d.graph_tails.collect {|tail| tail.title }.sort
  end
end
