# Configuration file for jupyterhub (postgres example).
from batchspawner import SlurmSpawner
class MySpawner(SlurmSpawner):
    exec_prefix = ""
    batch_submit_cmd = "sudo -E -u {username} sbatch --parsable"
    batch_cancel_cmd = "sudo -u {username} scancel {jobid}"
    @property
    def batch_script(self):
        with open('/etc/jupyterhub/submit.sh', 'r') as script_template:
            script = script_template.read()
        return script

c.JupyterHub.spawner_class = MySpawner
c.JupyterHub.hub_ip = '0.0.0.0'
c.JupyterHub.ip = '127.0.0.1'
c.JupyterHub.allow_named_servers = True

c.PAMAuthenticator.open_sessions = False
c.PAMAuthenticator.service = "jupyterhub-login"

c.Authenticator.admin_users = {'admin'}
c.JupyterHub.admin_access = True