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
    
    ---
    : tag           # tags
    + sha           # parent (sha) - child (commit)
    ~ sha           # previous (sha) - current (commit)
    - sha           # delete (sha)

The commit tree points to message attachments.

Non-node commits are indicated by lacking the tail section (for example
merges). The tree for non-node commits can be anything as they are ignored.

Distribution
----------

Standard branch distribution. Merges can be accomplished using any technique
so long as the merge commit is not a node (see above). The plan is to
implement a custom merge strategy that always results in an empty tree.

Processing
----------

Print the log and awk to list the graph data like:

    0/A (A) # node
    A/B (B) # edge, link
    A/B (A) # edge, update
    A/A (A) # node, delete

Then sort nodes into threads. For each line if collection A exists, append A/B
and reference collection B to A. Otherwise create collection A, append A, and
then continue. For 0, append "A" (the all index). The unique collections will
be sorted graphs for each thread.

Then deconvolute graphs so that updates and deletes are made current. Once
deconvoluted the graph can be written as a commit tree and inspected with
normal git tools. Update the deconvoluted graph as new data becomes available.

Update:

    A/B  (B)
    B/B1 (B)

Replace A/B with A/B1.  B will no longer be accessible.

Delete:

    A/A (A)

Replace x/A with x/x. This rule includes the A/A line - A is now a separate
node, still accessible if desired but identifiable as a detached head because
it has no head file.

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
