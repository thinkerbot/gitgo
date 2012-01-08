Gitgo
=========

Storage
---------

Use the file system to describe a set of graphs:

    0/A (A) # vertex -- so each object is stored at least once
    A/B (B) # edge, link
    A/B (A) # edge, update
    A/A (A) # vertex, delete

Print the tree to list the graph data. Tsort to order properly.  For each line if file A exists, append "A/B" and symlink B to A.  Otherwise create A, write A, and then continue.  For 0, append "A" (the all index).  Remove all symlinks and the result will be sorted graphs named for each head.  When displaying, these represent each thread or issue.  The files can receive any new edges, but will need to be sorted afterwards.

Use a commit for each vertex, with a special format for the message.

    tree
    parent
    author name <email> date zone
        
    summary
    
    body...
    
    tag tag tag

The commit tree points to a tree with any attachments in it.  The parent(s) identify commits in the main branches where the issue/comment applies.

Searches
---------

Traverse each object and index by name, email, date (day granularity, utc), and tags.  The indexes allow quick searches for activity by a user, or tagged in a particular way.  Tags should include categories like 'issue' or 'page', as applicable.  The indexes are files of shas, separated by lines.

To search for:

* A category - list all heads and find common lines (comm)
* Activity   - grep index for input
* Heads      - grep head files for sha

Combine searches as needed to get the desired results.

Display
---------

The full graph can be deconvoluted so that updates and deletes are made current.  Once deconvoluted the graph can e written as a commit tree and inspected with normal git tools.  Expire the branch on updates to the issue. In the tree, track the issue content and attachments. Allow checkout of it in that way and thereby make the issue available in another way.  Further work on the branch is meaningless, however.

Update:

    A/B  (B)
    B/B1 (B)

Replace A/B with A/B1 (sed).  B will no longer be accessible.

Delete:

    A/A (A)

Replace x/A with x/x. This rule includes the A/A line - A is now a separate vertex, still accessible if desired but identifiable as a detached head because it has no head file.
