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
  Array[String] $jupyterlab_disabled_extensions = [],
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

  # Frozen deps command : 
  # /opt/jupyterhub_node/bin/pip freeze | tr '_' '-' | tr '[:upper:]' '[:lower:]' | \
  # grep -v -P '^(jupyterhub|jupyterlab|notebook|batchspawner|jupyter-remote-desktop-proxy|
  # jupyter-rsession-proxy|jupyter-server-proxy|jupyterlab-nvdashboard|jupyterlmod|nbgitpuller|
  # ipywidgets|widgetsnbextension|jupyterlab_widget)=='

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

  # Build the base set of disabled extensions
  if $jupyterlmod_version and $jupyter_server_proxy_version {
    $base_disabled = { '@jupyterhub/jupyter-server-proxy' => true }

    # disable jupyter-server-proxy nbextension
    file { "${prefix}/etc/jupyter/nbconfig/tree.d/jupyter-server-proxy.json":
      content   => '{"load_extensions": {"jupyter_server_proxy/tree": false}}',
      subscribe => Uv::Venv['node'],
    }
  } else {
    $base_disabled = {}
  }

  # Convert the disabled_extensions array to the hash format required by page_config.json
  $jupyterlab_disabled_hash = $jupyterlab_disabled_extensions.reduce({}) |$result, $ext| {
    $result + { $ext => true }
  }

  # When user specifies extensions to disable, also disable the Extension Manager
  # and Plugin Manager to prevent users from installing or re-enabling extensions
  if !empty($jupyterlab_disabled_extensions) {
    $manager_disabled = {
      '@jupyterlab/extensionmanager-extension' => true,
      '@jupyterlab/pluginmanager-extension'    => true,
    }
  } else {
    $manager_disabled = {}
  }

  # Merge all disabled extension sources
  $all_disabled = $base_disabled + $manager_disabled + $jupyterlab_disabled_hash

  if !empty($all_disabled) {
    $page_config = { 'disabledExtensions' => $all_disabled }

    ensure_resource('file', "${prefix}/etc/jupyter/labconfig/", {
      'ensure'  => 'directory',
      'require' => Uv::Venv['node'],
    })
    file { "${prefix}/etc/jupyter/labconfig/page_config.json":
      content   => to_json_pretty($page_config, true),
      subscribe => Uv::Venv['node'],
      require   => File["${prefix}/etc/jupyter/labconfig/"],
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
