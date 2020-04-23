class jupyterhub::node (
  Stdlib::Absolutepath $prefix = '/opt/jupyterhub',
  Optional[String] $http_proxy = undef,
  Optional[String] $https_proxy = undef,
) {
  if ($http_proxy != undef and $https_proxy != undef){
    # Lets use a proxy for all the pip install
    Exec {
      environment => ["http_proxy=${http_proxy}", "https_proxy=${https_proxy}"],
    }
  }

  class { 'jupyterhub::base':
    prefix => $prefix
  }
  class { 'jupyterhub::node::install':
    prefix => $prefix
  }
  $kernel_setup = lookup('jupyterhub::kernel::setup', Enum['venv', 'module'], undef, 'venv')
  if $kernel_setup == 'venv' {
    include jupyterhub::kernel::venv
  }
}

class jupyterhub::node::install (Stdlib::Absolutepath $prefix) {
  exec { 'pip_notebook':
    command => "${prefix}/bin/pip install --no-cache-dir notebook",
    creates => "${prefix}/lib/python3.6/site-packages/notebook/",
    require => Exec['jupyterhub_venv']
  }


  # This makes sure the /opt/jupyterhub install does not provide the default kernel.
  # The kernel is provided by the local install in /opt/ipython-kernel.
  exec { 'pip_uninstall_ipykernel':
    command => "${prefix}/bin/pip uninstall -y ipykernel ipython prompt-toolkit wcwidth pickleshare backcall pexpect jedi parso",
    onlyif  => "/usr/bin/test -f ${prefix}/lib/python3.6/site-packages/ipykernel_launcher.py",
    require => Exec['pip_notebook']
  }

  # This make sure that the removal of ipykernel does not cause exception when using
  # pkg_resources module. This was found out when trying to load jupyter-rsession-proxy
  # JupyterLab. The extension could not load unless the ipykernel requirement was removed
  # from notebook metadata.
  exec { 'sed_notebook_metadata':
    command     => "/usr/bin/sed -i '/^Requires-Dist: ipykernel$/d' ${prefix}/lib/python3.6/site-packages/notebook-*.dist-info/METADATA",
    subscribe   => Exec['pip_notebook'],
    refreshonly => true,
  }

  exec { 'pip_jupyterlab':
    command => "${prefix}/bin/pip install --no-cache-dir jupyterlab",
    creates => "${prefix}/lib/python3.6/site-packages/jupyterlab/",
    require => Exec['jupyterhub_venv']
  }

  exec { 'pip_jupyterlmod':
    command => "${prefix}/bin/pip install --no-cache-dir jupyterlmod",
    creates => "${prefix}/lib/python3.6/site-packages/jupyterlmod/",
    require => Exec['pip_notebook']
  }

  exec { 'pip_jupyter-server-proxy':
    command => "${prefix}/bin/pip install --no-cache-dir jupyter-server-proxy",
    creates => "${prefix}/lib/python3.6/site-packages/jupyter_server_proxy/",
    require => Exec['pip_notebook']
  }

  exec { 'pip_nbzip':
    command => "${prefix}/bin/pip install --no-cache-dir --no-deps nbzip",
    creates => "${prefix}/lib/python3.6/site-packages/nbzip",
    require => Exec['pip_notebook']
  }

  exec { 'jupyter-labextension-lmod':
    command => "${prefix}/bin/jupyter labextension install --minimize=False jupyterlab-lmod",
    creates => "${prefix}/share/jupyter/lab/staging/node_modules/jupyterlab-lmod",
    timeout => 0,
    require => Exec['pip_jupyterlab'],
  }

  $jupyter_notebook_config_hash = lookup('jupyterhub::jupyter_notebook_config_hash', undef, undef, {})
  file { 'jupyter_notebook_config.json' :
    ensure  => present,
    path    => "${prefix}/etc/jupyter/jupyter_notebook_config.json",
    content => to_json_pretty($jupyter_notebook_config_hash, true),
    mode    => '0644'
  }

  file { 'nbzip_enable_nbserver_extension' :
    ensure  => present,
    path    => "${prefix}/etc/jupyter/jupyter_notebook_config.d/nbzip.json",
    content => '{ "NotebookApp": { "nbserver_extensions": { "nbzip": true } } }',
    mode    => '0644'
  }

  exec { 'install_nbzip_nb':
    command => "${prefix}/bin/jupyter nbextension install --py nbzip --sys-prefix",
    creates => "${prefix}/share/jupyter/nbextensions/nbzip",
    require => Exec['pip_nbzip']
  }

  exec { 'enable_nbzip_nb':
    command => "${prefix}/bin/jupyter nbextension enable --py nbzip --sys-prefix",
    unless  => "/usr/bin/grep -q nbzip/tree ${prefix}/etc/jupyter/nbconfig/tree.json",
    require => Exec['pip_nbzip']
  }

  file { "${prefix}/lib/usercustomize":
    ensure => 'directory',
    mode   => '0755',
  }

  file { "${prefix}/lib/usercustomize/usercustomize.py":
    source => 'puppet:///modules/jupyterhub/usercustomize.py',
    mode   => '0655',
  }
}
