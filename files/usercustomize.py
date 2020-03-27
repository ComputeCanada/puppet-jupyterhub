import site
import os
import sys

pip_prefix = os.environ.get('PIP_PREFIX', None)
if pip_prefix:
    path = os.path.join(pip_prefix, 'lib', 'python' + sys.version[:3], 'site-packages')
    # Make sure the PIP_PREFIX is prepended to sys.path and not appended
    # by keeping a reference to the old path list, then replace it by a clean list
    # to which site will add our pip_prefix path, then we merge the old sys.path
    # content.
    prev_syspath = sys.path
    sys.path = []
    site.addsitedir(path)
    sys.path.extend(prev_syspath)
