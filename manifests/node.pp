class jupyterhub::node (
  Stdlib::Absolutepath $prefix = $jupyterhub::prefix,
  Optional[String] $http_proxy = undef,
  Optional[String] $https_proxy = undef,
) {
  if ($http_proxy != undef and $https_proxy != undef){
    # Lets use a proxy for all the pip install
    Exec {
      environment => ["http_proxy=${http_proxy}", "https_proxy=${https_proxy}"],
    }
  }

  include jupyterhub::base

  class { 'jupyterhub::node::install':
    prefix => $prefix
  }
  $kernel_setup = lookup('jupyterhub::kernel::setup', Enum['venv', 'module'], undef, 'venv')
  if $kernel_setup == 'venv' {
    include jupyterhub::kernel::venv
  }
}

class jupyterhub::node::install (Stdlib::Absolutepath $prefix) {
  $notebook_version = lookup('jupyterhub::notebook::version')
  $jupyterlab_version = lookup('jupyterhub::jupyterlab::version')
  $jupyter_server_proxy_version = lookup('jupyterhub::jupyter_server_proxy::version')
  $jupyterlmod_version = lookup('jupyterhub::jupyterlmod::version')
  $jupyterlab_nvdashboard_version = lookup('jupyterhub::jupyterlab_nvdashboard::version')
  $jupyter_rsession_proxy_version = lookup('jupyterhub::jupyter_rsession_proxy::version')
  $jupyter_rsession_proxy_url = lookup('jupyterhub::jupyter_rsession_proxy::url')
  $jupyter_desktop_server_url = lookup('jupyterhub::jupyter_desktop_server::url')
  $python3_version = lookup('jupyterhub::python3::version')

  exec { 'pip_notebook':
    command => "${prefix}/bin/pip install --no-cache-dir notebook==${notebook_version}",
    creates => "${prefix}/lib/python${python3_version}/site-packages/notebook-${notebook_version}.dist-info/",
    require => Exec['jupyterhub_venv']
  }

  # This make sure that the removal of ipykernel does not cause exception when using
  # pkg_resources module. This was found out when trying to load jupyter-rsession-proxy
  # JupyterLab. The extension could not load unless the ipykernel requirement was removed
  # from notebook metadata.
  exec { 'sed_notebook_metadata':
    command => "/usr/bin/sed -i '/^Requires-Dist: ipykernel$/d' ${prefix}/lib/python${python3_version}/site-packages/notebook-*.dist-info/METADATA",
    onlyif  => "/usr/bin/grep -q '^Requires-Dist: ipykernel$' ${prefix}/lib/python${python3_version}/site-packages/notebook-*.dist-info/METADATA",
    require => Exec['pip_notebook'],
  }

  exec { 'pip_jupyterlab':
    command => "${prefix}/bin/pip install --no-cache-dir jupyterlab==${jupyterlab_version}",
    creates => "${prefix}/lib/python${python3_version}/site-packages/jupyterlab-${jupyterlab_version}.dist-info/",
    require => Exec['jupyterhub_venv'],
    before  => Exec['pip_uninstall_ipykernel'],
  }

  exec { 'pip_jupyterlmod':
    command => "${prefix}/bin/pip install --no-cache-dir jupyterlmod==${jupyterlmod_version}",
    creates => "${prefix}/lib/python${python3_version}/site-packages/jupyterlmod-${jupyterlmod_version}.dist-info/",
    require => Exec['pip_notebook'],
    before  => Exec['pip_uninstall_ipykernel'],
  }

  exec { 'pip_jupyter-server-proxy':
    command => "${prefix}/bin/pip install --no-cache-dir jupyter-server-proxy==${jupyter_server_proxy_version}",
    creates => "${prefix}/lib/python${python3_version}/site-packages/jupyter_server_proxy-${jupyter_server_proxy_version}.dist-info/",
    require => Exec['pip_notebook'],
    before  => Exec['pip_uninstall_ipykernel'],
  }

  # exec { 'pip_jupyter-rsession-proxy':
  #   command => "${prefix}/bin/pip install --no-cache-dir jupyter-rsession-proxy==${jupyter_rsession_proxy_version}",
  #   creates => "${prefix}/lib/python${python3_version}/site-packages/jupyter_rsession_proxy-${jupyter_rsession_proxy_version}.dist-info/",
  #   require => Exec['pip_jupyter-server-proxy']
  # }

  exec { 'pip_jupyter-rsession-proxy':
    command => "${prefix}/bin/pip install --no-cache-dir ${jupyter_rsession_proxy_url}",
    creates => "${prefix}/lib/python${python3_version}/site-packages/jupyter_rsession_proxy/",
    require => Exec['pip_jupyter-server-proxy'],
    before  => Exec['pip_uninstall_ipykernel'],
  }

  exec { 'pip_jupyter-desktop-server':
    command => "${prefix}/bin/pip install --no-cache-dir ${jupyter_desktop_server_url}",
    creates => "${prefix}/lib/python${python3_version}/site-packages/jupyter_desktop/",
    require => Exec['pip_jupyter-server-proxy'],
    before  => Exec['pip_uninstall_ipykernel'],
  }

  exec { 'pip_nbzip':
    command => "${prefix}/bin/pip install --no-cache-dir --no-deps nbzip",
    creates => "${prefix}/lib/python${python3_version}/site-packages/nbzip",
    require => Exec['pip_notebook'],
    before  => Exec['pip_uninstall_ipykernel'],
  }

  exec { 'jupyter-labextension-lmod':
    command => "${prefix}/bin/jupyter labextension install --minimize=False jupyterlab-lmod",
    creates => "${prefix}/share/jupyter/lab/staging/node_modules/jupyterlab-lmod",
    timeout => 0,
    require => Exec['pip_jupyterlab'],
    before  => Exec['pip_uninstall_ipykernel'],
  }

  exec { 'pip_jupyterlab-nvdashboard':
    command => "${prefix}/bin/pip install --no-cache-dir jupyterlab_nvdashboard==${jupyterlab_nvdashboard_version}",
    creates => "${prefix}/lib/python${python3_version}/site-packages/jupyterlab_nvdashboard-${jupyterlab_nvdashboard_version}.dist-info/",
    timeout => 0,
    require => Exec['pip_jupyterlab'],
    before  => Exec['pip_uninstall_ipykernel'],
  }

  exec { 'jupyter-labextension-server-proxy':
    command     => "${prefix}/bin/jupyter labextension disable jupyterlab-server-proxy",
    timeout     => 0,
    subscribe   => Exec['pip_jupyter-server-proxy'],
    refreshonly => true,
    before      => Exec['pip_uninstall_ipykernel'],
  }

  exec { 'jupyter-nbextension-server-proxy':
    command     => "${prefix}/bin/jupyter nbextension disable --py jupyter_server_proxy --sys-prefix",
    timeout     => 0,
    subscribe   => Exec['pip_jupyter-server-proxy'],
    refreshonly => true,
    before      => Exec['pip_uninstall_ipykernel'],
  }

  $jupyter_notebook_config_hash = lookup('jupyterhub::jupyter_notebook_config_hash', undef, undef, {})
  file { 'jupyter_notebook_config.json' :
    ensure  => present,
    path    => "${prefix}/etc/jupyter/jupyter_notebook_config.json",
    content => to_json_pretty($jupyter_notebook_config_hash, true),
    mode    => '0644',
  }

  file { 'jupyter_server_config.json' :
    ensure  => present,
    path    => "${prefix}/etc/jupyter/jupyter_server_config.json",
    content => to_json_pretty($jupyter_notebook_config_hash, true),
    mode    => '0644',
  }

  file { 'nbzip_enable_nbserver_extension' :
    ensure  => present,
    path    => "${prefix}/etc/jupyter/jupyter_notebook_config.d/nbzip.json",
    content => '{ "NotebookApp": { "nbserver_extensions": { "nbzip": true } } }',
    mode    => '0644',
  }

  exec { 'install_nbzip_nb':
    command => "${prefix}/bin/jupyter nbextension install --py nbzip --sys-prefix",
    creates => "${prefix}/share/jupyter/nbextensions/nbzip",
    require => Exec['pip_nbzip'],
    before  => Exec['pip_uninstall_ipykernel'],
  }

  exec { 'enable_nbzip_nb':
    command => "${prefix}/bin/jupyter nbextension enable --py nbzip --sys-prefix",
    unless  => "/usr/bin/grep -q nbzip/tree ${prefix}/etc/jupyter/nbconfig/tree.json",
    require => Exec['pip_nbzip'],
    before  => Exec['pip_uninstall_ipykernel'],
  }

  # This makes sure the /opt/jupyterhub install does not provide the default kernel.
  # The kernel is provided by the local install in /opt/ipython-kernel.
  exec { 'pip_uninstall_ipykernel':
    command => "${prefix}/bin/pip uninstall -y ipykernel ipython prompt-toolkit wcwidth pickleshare backcall pexpect jedi parso",
    onlyif  => "/usr/bin/test -f ${prefix}/lib/python${$python3_version}/site-packages/ipykernel_launcher.py",
    require => Exec['pip_notebook'],
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
