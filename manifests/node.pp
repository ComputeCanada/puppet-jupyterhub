class jupyterhub::node (
  Stdlib::Absolutepath $prefix = '/opt/jupyterhub',
  Array[String] $packages = [],
  Optional[String] $http_proxy = undef,
  Optional[String] $https_proxy = undef,
) {
  if ($http_proxy != undef and $https_proxy != undef) {
    # Lets use a proxy for all the pip install
    Exec {
      environment => ["http_proxy=${http_proxy}", "https_proxy=${https_proxy}"],
    }
  }

  ensure_resource('class', 'jupyterhub::base', { 'prefix' => $prefix })

  class { 'jupyterhub::node::install':
    prefix   => $prefix,
    packages => $packages,
  }
  $kernel_setup = lookup('jupyterhub::kernel::setup', Enum['venv', 'module'], undef, 'venv')
  if $kernel_setup == 'venv' {
    include jupyterhub::kernel::venv
  }
}

class jupyterhub::node::install (
  Stdlib::Absolutepath $prefix
  Array[String] $packages = [],
) {
  $jupyterhub_version = lookup('jupyterhub::jupyterhub::version')
  $batchspawner_version = lookup('jupyterhub::batchspawner::version')
  $notebook_version = lookup('jupyterhub::notebook::version')
  $jupyterlab_version = lookup('jupyterhub::jupyterlab::version')
  $jupyter_server_proxy_version = lookup('jupyterhub::jupyter_server_proxy::version')
  $jupyterlmod_version = lookup('jupyterhub::jupyterlmod::version')
  $bokeh_version = lookup('jupyterhub::bokeh::version')
  $jupyterlab_nvdashboard_version = lookup('jupyterhub::jupyterlab_nvdashboard::version')
  $jupyter_rsession_proxy_version = lookup('jupyterhub::jupyter_rsession_proxy::version')
  $jupyter_desktop_server_url = lookup('jupyterhub::jupyter_desktop_server::url')
  $python3_version = lookup('jupyterhub::python3::version')

  file { "${prefix}/node-requirements.txt":
    content => epp('jupyterhub/node-requirements.txt', {
        'jupyterhub_version'             => $jupyterhub_version,
        'batchspawner_version'           => $batchspawner_version,
        'notebook_version'               => $notebook_version,
        'jupyterlab_version'             => $jupyterlab_version,
        'jupyter_server_proxy_version'   => $jupyter_server_proxy_version,
        'jupyterlmod_version'            => $jupyterlmod_version,
        'bokeh_version'                  => $bokeh_version,
        'jupyterlab_nvdashboard_version' => $jupyterlab_nvdashboard_version,
        'jupyter_rsession_proxy_version' => $jupyter_rsession_proxy_version,
        'jupyter_desktop_server_url'     => $jupyter_desktop_server_url,
    }),
    mode    => '0644',
  }

  exec { 'node_pip_install':
    command     => "uv pip install --no-deps -r ${prefix}/node-requirements.txt",
    path        => ['/opt/uv/bin'],
    environment => ["VIRTUAL_ENV=${prefix}"],
    require     => Exec['jupyterhub_venv'],
    subscribe   => File["${prefix}/node-requirements.txt"],
    refreshonly => true,
  }

  if length($packages) > 0 {
    file { "${prefix}/node-extra-requirements.txt":
      content => join($packages, '\n'),
    }

    exec { 'node_pip_install_extra':
      command     => "uv pip install -r ${prefix}/node-extra-requirements.txt",
      path        => ['/opt/uv/bin'],
      environment => ["VIRTUAL_ENV=${prefix}"],
      require     => Exec['node_pip_install'],
      subscribe   => File["${prefix}/node-extra-requirements.txt"],
      refreshonly => true,
    }
  }

  # This make sure that the removal of ipykernel does not cause exception when using
  # pkg_resources module. This was found out when trying to load jupyter-rsession-proxy
  # JupyterLab. The extension could not load unless the ipython and ipykernel requirement
  # were removed from notebook metadata.
  $ipy_grep = "grep -l -E 'Requires-Dist: (ipykernel|ipython)' ${prefix}/lib/python${python3_version}/site-packages/*.dist-info/METADATA"
  exec { 'sed_out_ipy_metadata':
    command => "${ipy_grep} | xargs sed -i -E '/^Requires-Dist: ipykernel|ipython/d'",
    onlyif  => "${ipy_grep} -q",
    path    => ['/usr/bin'],
    require => Exec['node_pip_install'],
  }

  # disable jupyterlab-server-proxy extension
  file { "${prefix}/etc/jupyter/labconfig/page_config.json":
    content   => '{"disabledExtensions": {"jupyterlab-server-proxy": true}}',
    subscribe => Exec['node_pip_install'],
  }

  # disable jupyter-server-proxy nbextension
  file { "${prefix}/etc/jupyter/nbconfig/tree.d/jupyter-server-proxy-nbextension.json":
    content   => '{"load_extensions": {"jupyter_server_proxy/tree": false}}',
    subscribe => Exec['node_pip_install'],
  }

  $jupyter_notebook_config_hash = lookup('jupyterhub::jupyter_notebook_config_hash', undef, undef, {})
  file { 'jupyter_notebook_config.json' :
    path    => "${prefix}/etc/jupyter/jupyter_notebook_config.json",
    content => to_json_pretty($jupyter_notebook_config_hash, true),
    mode    => '0644',
    require => Exec['node_pip_install'],
  }

  file { 'jupyter_server_config.json' :
    path    => "${prefix}/etc/jupyter/jupyter_server_config.json",
    content => to_json_pretty($jupyter_notebook_config_hash, true),
    mode    => '0644',
    require => Exec['node_pip_install'],
  }

  file { "${prefix}/lib/usercustomize":
    ensure  => 'directory',
    mode    => '0755',
    require => Exec['jupyterhub_venv'],
  }

  file { "${prefix}/lib/usercustomize/usercustomize.py":
    source  => 'puppet:///modules/jupyterhub/usercustomize.py',
    mode    => '0655',
    require => Exec['jupyterhub_venv'],
  }
}
