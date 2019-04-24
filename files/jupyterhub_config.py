c.JupyterHub.spawner_class = 'slurmformspawner.SlurmFormSpawner'
c.JupyterHub.hub_ip = '0.0.0.0'
c.JupyterHub.ip = '127.0.0.1'
c.JupyterHub.allow_named_servers = True

c.PAMAuthenticator.open_sessions = False
c.PAMAuthenticator.service = "jupyterhub-login"

c.Authenticator.admin_users = {'admin'}
c.JupyterHub.admin_access = True