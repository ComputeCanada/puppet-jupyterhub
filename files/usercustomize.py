import site
import os
import sys

pip_prefix = os.environ.get('PIP_PREFIX', None)
if pip_prefix:
    path = os.path.join(pip_prefix, 'lib', 'python' + sys.version[:3], 'site-packages')
    site.addsitedir(path)
