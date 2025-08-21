class jupyterhub::node (
  Enum['none', 'venv'] $install_method = 'venv',
) {
  include jupyterhub::node::config
  include jupyterhub::kernel

  if $install_method == 'venv' {
    include jupyterhub::node::install
  }
}

class jupyterhub::node::config {
  $jupyter_notebook_config_hash = lookup('jupyterhub::jupyter_notebook_config_hash', undef, undef, {})

  ensure_resource('file', '/etc/jupyter', { 'ensure' => 'directory' })

  file { 'jupyter_notebook_config.json' :
    path    => '/etc/jupyter/jupyter_notebook_config.json',
    content => to_json_pretty($jupyter_notebook_config_hash, true),
    mode    => '0644',
    require => File['/etc/jupyter'],
  }

  file { 'jupyter_server_config.json' :
    path    => '/etc/jupyter/jupyter_server_config.json',
    content => to_json_pretty($jupyter_notebook_config_hash, true),
    mode    => '0644',
    require => File['node_pip_install'],
  }
}

class jupyterhub::node::install (
  Stdlib::Absolutepath $prefix = '/opt/jupyterhub',
  Array[String] $packages = [],
) {
  include jupyterhub::uv::install
  ensure_resource('class', 'jupyterhub::base::install', { 'prefix' => $prefix })

  $jupyterhub_version = lookup('jupyterhub::jupyterhub::version')
  $batchspawner_version = lookup('jupyterhub::batchspawner::version')
  $nbgitpuller_version = lookup('jupyterhub::nbgitpuller::version')
  $ipywidgets_version = lookup('jupyterhub::ipywidgets::version')
  $widgetsnbextension_version = lookup('jupyterhub::widgetsnbextension::version')
  $jupyterlab_widgets_version = lookup('jupyterhub::jupyterlab_widgets::version')
  $notebook_version = lookup('jupyterhub::notebook::version')
  $jupyterlab_version = lookup('jupyterhub::jupyterlab::version')
  $jupyter_server_proxy_version = lookup('jupyterhub::jupyter_server_proxy::version')
  $jupyterlmod_version = lookup('jupyterhub::jupyterlmod::version')
  $jupyterlab_nvdashboard_version = lookup('jupyterhub::jupyterlab_nvdashboard::version')
  $jupyter_rsession_proxy_version = lookup('jupyterhub::jupyter_rsession_proxy::version')
  $jupyter_desktop_server_url = lookup('jupyterhub::jupyter_desktop_server::url')
  $python3_version = lookup('jupyterhub::python3::version')

  file { "${prefix}/node-requirements.txt":
    content => epp('jupyterhub/node-requirements.txt', {
        'jupyterhub_version'             => $jupyterhub_version,
        'batchspawner_version'           => $batchspawner_version,
        'notebook_version'               => $notebook_version,
        'nbgitpuller_version'            => $nbgitpuller_version,
        'ipywidgets_version'             => $ipywidgets_version,
        'widgetsnbextension_version'     => $widgetsnbextension_version,
        'jupyterlab_widgets_version'     => $jupyterlab_widgets_version,
        'jupyterlab_version'             => $jupyterlab_version,
        'jupyter_server_proxy_version'   => $jupyter_server_proxy_version,
        'jupyterlmod_version'            => $jupyterlmod_version,
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

  if $jupyterlmod_version and $jupyter_server_proxy_version {
    # disable jupyterlab-server-proxy extension
    ensure_resource('file', "${prefix}/etc/jupyter/labconfig/", { 'ensure' => 'directory' })
    file { "${prefix}/etc/jupyter/labconfig/page_config.json":
      content   => '{"disabledExtensions": {"@jupyterhub/jupyter-server-proxy": true}}',
      subscribe => Exec['node_pip_install'],
      require   => File["${prefix}/etc/jupyter/labconfig/"],
    }

    # disable jupyter-server-proxy nbextension
    file { "${prefix}/etc/jupyter/nbconfig/tree.d/jupyter-server-proxy.json":
      content   => '{"load_extensions": {"jupyter_server_proxy/tree": false}}',
      subscribe => Exec['node_pip_install'],
    }
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
