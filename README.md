Gitgo
=========

Provides a mechanism to store issues in git and distribute them in a
conflict-free way.

Conversations are treated as directed acyclic graphs where each node is a
message in a thread. Nodes may be added to the graphs, but like commits they
may not be changed or deleted directly. However, nodes may be flagged to
replace or detach other nodes and the graph deconvoluted such that replaced
and detached nodes are not present. This providing a mechanism to logically
update and delete parts of the graph without literally updating or removing
nodes.

During deconvolution a replacement node removes the replaced node from the 
graph and inherits edges of the replaced node.  A detach node removes the
detached node and any edges of the detached node.

The conversation nodes are as normal by commits in git on a dedicated branch.
Metadata is stored in a section appended to the commit message. Trees are used
to store attachments and have no specific meaning. Merges can be accomplished
by assigning an empty tree.

One application of this system is to allow distributed issue tracking.  Other
conversations like wiki pages and code comments are likewise possible.

Storage
---------

Use a commit for each node, with a special format for the message.

    tree
    parent
    author name <email> date zone
        
    summary
    
    body...
    
    tag tag tag     # store with command line escaping if spaces needed
    actions         # one per-line as below

Actions are:

    + sha           # add as child (commit) to parent (sha)
    ~ sha           # update vertex
    - sha           # delete vertex

The commit tree points to message attachments.

Processing
----------

Print the log and awk to list the graph data like:

    0/A (A) # vertex
    A/B (B) # edge, link
    A/B (A) # edge, update
    A/A (A) # vertex, delete

For each line if file A exists, append "A/B" and symlink B to A. Otherwise
create A, write A, and then continue. For 0, append "A" (the all index).
Remove all symlinks and the result will be sorted graphs named for each head.
When displaying, these represent each thread or issue. The files can receive
any new edges, but will need to be sorted afterwards.

Searches
---------

Traverse each object and index by name, email, date (day granularity, utc),
and tags. The indexes allow quick searches for activity by a user, or tagged
in a particular way. Tags should include categories like 'issue' or 'page', as
applicable. The indexes are files of shas, separated by lines.

To search for:

* A category - list all heads and find common lines (comm)
* Activity   - grep index for input
* Heads      - grep head files for sha

Combine searches as needed to get the desired results.

Display
---------

The full graph can be deconvoluted so that updates and deletes are made
current. Once deconvoluted the graph can e written as a commit tree and
inspected with normal git tools. Expire the branch on updates to the issue. In
the tree, track the issue content and attachments. Allow checkout of it in
that way and thereby make the issue available in another way. Further work on
the branch is meaningless, however.

Update:

    A/B  (B)
    B/B1 (B)

Replace A/B with A/B1 (sed).  B will no longer be accessible.

Delete:

    A/A (A)

Replace x/A with x/x. This rule includes the A/A line - A is now a separate
vertex, still accessible if desired but identifiable as a detached head
because it has no head file.
