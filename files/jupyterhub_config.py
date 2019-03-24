# Configuration file for jupyterhub (postgres example).
from batchspawner import SlurmSpawner
class MySpawner(SlurmSpawner):
    @property
    def batch_script(self):
        with open('/opt/jupyterhub/etc/submit.sh', 'r') as script_template:
            script = script_template.read()
        return script
c.JupyterHub.spawner_class = MySpawner
c.JupyterHub.hub_ip = '0.0.0.0'
c.JupyterHub.ip = '127.0.0.1'

c.PAMAuthenticator.open_sessions = False
c.Authenticator.admin_users = {'admin'}
c.JupyterHub.admin_access = True