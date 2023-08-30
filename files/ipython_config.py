c = get_config()  #noqa
# Move IPython history to in-memory sqlite instead of on-disk.
# This avoids kernel hanging issues with network filesystem like Lustre and NFS.
c.HistoryAccessor.hist_file = ":memory:"