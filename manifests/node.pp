class jupyterhub::node (
  Stdlib::Absolutepath $prefix,
  Enum['none', 'venv'] $install_method,
) {
  include jupyterhub::node::config
  include jupyterhub::kernel

  if $install_method == 'venv' {
    include jupyterhub::node::install
  }
}

class jupyterhub::node::config (
  Hash $jupyter_server_config = {}
) {
  ensure_resource('file', '/etc/jupyter', { 'ensure' => 'directory' })

  file { 'jupyter_notebook_config.json':
    path    => '/etc/jupyter/jupyter_notebook_config.json',
    content => to_json_pretty($jupyter_server_config, true),
    mode    => '0644',
    require => File['/etc/jupyter'],
  }

  file { 'jupyter_server_config.json':
    path    => '/etc/jupyter/jupyter_server_config.json',
    content => to_json_pretty($jupyter_server_config, true),
    mode    => '0644',
    require => File['/etc/jupyter'],
  }
}

class jupyterhub::node::install (
  String $python,
  Array[String] $packages = [],
  Boolean $frozen_deps = true,
) {
  include uv::install
  $prefix = lookup('jupyterhub::node::prefix')

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
  $jupyter_remote_desktop_proxy_version = lookup('jupyterhub::jupyter_remote_desktop_proxy::version')

  uv::venv { 'node':
    prefix       => $prefix,
    python       => $python,
    requirements => epp('jupyterhub/node-requirements.txt', {
        'jupyterhub_version'                   => $jupyterhub_version,
        'batchspawner_version'                 => $batchspawner_version,
        'notebook_version'                     => $notebook_version,
        'nbgitpuller_version'                  => $nbgitpuller_version,
        'ipywidgets_version'                   => $ipywidgets_version,
        'widgetsnbextension_version'           => $widgetsnbextension_version,
        'jupyterlab_widgets_version'           => $jupyterlab_widgets_version,
        'jupyterlab_version'                   => $jupyterlab_version,
        'jupyter_server_proxy_version'         => $jupyter_server_proxy_version,
        'jupyterlmod_version'                  => $jupyterlmod_version,
        'jupyterlab_nvdashboard_version'       => $jupyterlab_nvdashboard_version,
        'jupyter_rsession_proxy_version'       => $jupyter_rsession_proxy_version,
        'jupyter_remote_desktop_proxy_version' => $jupyter_remote_desktop_proxy_version,
        'frozen_deps'                          => $frozen_deps,
        'extra_packages'                       => $packages,
    }),
  }

  if $jupyterlmod_version and $jupyter_server_proxy_version {
    # disable jupyterlab-server-proxy extension
    ensure_resource('file', "${prefix}/etc/jupyter/labconfig/", { 'ensure' => 'directory', 'require' => Uv::Venv['node'] })
    file { "${prefix}/etc/jupyter/labconfig/page_config.json":
      content   => '{"disabledExtensions": {"@jupyterhub/jupyter-server-proxy": true}}',
      subscribe => Uv::Venv['node'],
      require   => File["${prefix}/etc/jupyter/labconfig/"],
    }

    # disable jupyter-server-proxy nbextension
    file { "${prefix}/etc/jupyter/nbconfig/tree.d/jupyter-server-proxy.json":
      content   => '{"load_extensions": {"jupyter_server_proxy/tree": false}}',
      subscribe => Uv::Venv['node'],
    }
  }

  file { "${prefix}/lib/usercustomize":
    ensure  => 'directory',
    mode    => '0755',
    require => Uv::Venv['node'],
  }

  file { "${prefix}/lib/usercustomize/usercustomize.py":
    source  => 'puppet:///modules/jupyterhub/usercustomize.py',
    mode    => '0655',
    require => Uv::Venv['node'],
  }

  file { "${prefix}/share/jupyter/kernels/python3/kernel.json":
    ensure  => absent,
    require => Uv::Venv['node'],
  }
}
