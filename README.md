# CloudCount

In progress test integrating automerge and NSDocument

File format:

1. Creaete an save a new document. Inspect the saved document package. Note that the package contents are also mirrored in the UI.

2. Incremenet and Decrement the count and save.

3. Notice file format writes small incremental changes. After 10 changes it then compacts these into a snapshot. The design is such that it should be possible for multiple users to concurrently edit a file, and for there changes to automatically merge.

4. The goal is that you can store this document format on iCloud and documents will automatically merge when concurrently edited. This works, but is a bit slow and messy.  

You can also use the Automerge test server to sync changes:

1. Create a new document
2. Send a copy of that document to another computer
3. Open both copies, and select the "Automerge Repo" checkbox for each document
4. The document should now syncs quickly using Automerges testing sever.
5. The sync is local first, and will catch up after being offline. For example disable wifi on one of the computers. Make changes on both computers. Then reanable wifi, and everything should sync again.

The automerge server sync is nice, but depending on your needs it leaves a lot of work to be done:

- For a real app you'll need to run your own sync sever
- There is no integration with apple accounts, or sharing
- Sync is performed without any accounts, you just have to know URL to participate

