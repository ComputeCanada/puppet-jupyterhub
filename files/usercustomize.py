import site
import os
import sys

pip_prefix = os.environ.get('PIP_PREFIX', None)
if pip_prefix:
    path = os.path.join(pip_prefix, 'lib', 'python{0}.{1}'.format(*sys.version_info), 'site-packages')
    # Make sure the PIP_PREFIX is prepended to sys.path and not appended
    # by keeping the sys path list length, all paths that were appended at the end
    # are moved at the beginning and the rest of the paths are appened at the end.
    len_syspath = len(sys.path)
    site.addsitedir(path)
    sys.path = sys.path[len_syspath:] + sys.path[:len_syspath]
