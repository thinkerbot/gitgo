require File.dirname(__FILE__) + "/../test_helper"
require 'gitgo/issues'

class IssuesTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include RepoTestHelper
  
  attr_reader :repo
  
  def setup
    super
    @repo = Gitgo::Repo.init(method_root[:tmp], :bare => true)
    app.set :repo, @repo
    app.instance_variable_set :@prototype, nil
  end
  
  def app
    Gitgo::Issues
  end
  
  #
  # post test
  #
  
  def test_post_creates_a_new_doc
    post("/issue", "content" => "Issue Description", "doc[title]" => "New Issue", "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    id = repo.timeline.last
    issue = repo.read(id)
    
    assert_equal "New Issue", issue['title']
    assert_equal "Issue Description", issue.content
    assert_equal app.author.email, issue.author.email
    
    assert_equal "/issue/#{id}", last_response['Location']
  end
  
  def test_post_links_issue_at_commit_referencing_issue
    commit = repo.set(:blob, "")
    
    post("/issue", "at" => commit, "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    issue = repo.timeline.last
    assert_equal [issue], repo.children(commit)
    assert_equal issue, repo.ref(commit, issue)
  end
  
  #
  # put test
  #
  
  def test_put_creates_a_comment_on_an_issue
    issue = repo.set(:blob, "New Issue")
    
    put("/issue/#{issue}", "content" => "Comment on the Issue", "commit" => "true")
    assert last_response.redirect?, last_response.body
    assert_equal "/issue/#{issue}", last_response['Location']
    
    id = repo.timeline.last
    comment = repo.read(id)
    
    assert_equal "Comment on the Issue", comment.content
    assert_equal app.author.email, comment.author.email
    assert_equal [id], repo.children(issue)
  end
  
  def test_put_links_comment_to_re
    issue = repo.set(:blob, "New Issue")
    a = repo.set(:blob, "Comment A")

    put("/issue/#{issue}", "content" => "Comment on A", "re" => a, "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    id = repo.timeline.last
    comment = repo.read(id)
    
    assert_equal "Comment on A", comment.content
    assert_equal [], repo.children(issue)
    assert_equal [id], repo.children(a)
  end
  
  def test_put_links_comment_to_multiple_re
    issue = repo.set(:blob, "New Issue")
    a = repo.set(:blob, "Comment A")
    b = repo.set(:blob, "Comment B")
    
    put("/issue/#{issue}", "content" => "Comment on A and B", "re" => [a, b], "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    id = repo.timeline.last
    comment = repo.read(id)
    
    assert_equal "Comment on A and B", comment.content
    assert_equal [], repo.children(issue)
    assert_equal [id], repo.children(a)
    assert_equal [id], repo.children(b)
  end
  
  def test_put_links_comment_at_commit_referencing_issue
    issue = repo.set(:blob, "New Issue")
    commit = repo.set(:blob, "")
    
    put("/issue/#{issue}", "at" => commit, "commit" => "true")
    assert last_response.redirect?, last_response.body
    
    comment = repo.timeline.last
    assert_equal [comment], repo.children(commit)
    assert_equal issue, repo.ref(commit, comment)
  end
  
  def test_put_raises_error_for_unknown_issue
    put("/issue/unknown", "content" => "Comment on the Issue", "commit" => "true")
    assert_equal 500, last_response.status
    
    assert last_response.body =~ /unknown issue: "unknown"/
  end
end