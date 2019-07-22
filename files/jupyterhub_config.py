c.JupyterHub.spawner_class = 'slurmformspawner.SlurmFormSpawner'
c.JupyterHub.hub_ip = '0.0.0.0'
c.JupyterHub.ip = '127.0.0.1'
c.JupyterHub.allow_named_servers = True
c.JupyterHub.ssl_key = '/etc/jupyterhub/ssl/key.pem'
c.JupyterHub.ssl_cert = '/etc/jupyterhub/ssl/cert.pem'

c.JupyterHub.authenticator_class = 'pammfauthenticator'
c.PAMAuthenticator.open_sessions = False
c.PAMAuthenticator.service = "jupyterhub-login"

c.Authenticator.admin_users = {'admin'}
c.JupyterHub.admin_access = True

c.Spawner.args = ['--KernelSpecManager.ensure_native_kernel=False']