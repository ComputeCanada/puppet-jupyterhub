# 
class jupyterhub::kernel::venv (
  String $python3_version,
  Stdlib::Absolutepath $prefix = '/opt/ipython-kernel',
  String $kernel_name = 'python3',
  String $display_name = 'Python 3',
  Array[String] $packages = [],
  Hash $pip_environment = {}
) {
  exec { 'kernel_venv':
    command     => "uv venv -p ${python3_version} ${prefix}",
    creates     => "${prefix}/bin/python",
    require     => Archive['jh_install_uv'],
    path        => ['/opt/uv/bin'],
    environment => ['XDG_DATA_HOME=/opt/uv/share'],
  }

  exec { 'pip_ipykernel':
    command     => 'uv pip install ipykernel',
    creates     => "${prefix}/bin/ipython",
    require     => Exec['kernel_venv'],
    environment => ["VIRTUAL_ENV=${prefix}"],
    path        => ['/opt/ub/bin'],
  }

  file { "${prefix}/etc":
    ensure  => directory,
    require => Exec['kernel_venv'],
  }

  file { "${prefix}/etc/ipython":
    ensure  => directory,
    require => File["${prefix}/etc"],
  }

  file { "${prefix}/etc/ipython/ipython_config.py":
    source => 'puppet:///modules/jupyterhub/ipython_config.py',
  }

  $node_prefix = $::jupyterhub::node::prefix
  exec { 'install_kernel':
    command => "python -m ipykernel install --name ${kernel_name} --display-name \"${display_name}\" --prefix ${node_prefix}",
    creates => "${node_prefix}/share/jupyter/kernels/${kernel_name}/kernel.json",
    require => [Exec['pip_ipykernel']],
    path    => ["${prefix}/bin"],
  }

  if (!$packages.empty) {
    $pip_env_list = $pip_environment.reduce([]) |Array $list, Array $value| {
      $list + ["${value[0]}=${value[1]}"]
    }

    $pkg_string = join($packages, "\n")

    file { "${prefix}/kernel-requirements.txt":
      content => $pkg_string,
    }

    exec { 'install_kernel_requirements_nodeps':
      command     => "uv pip install -r ${prefix}/kernel-requirements.txt",
      subscribe   => File["${prefix}/kernel-requirements.txt"],
      refreshonly => true,
      environment => $pip_env_list + ["VIRTUAL_ENV=${prefix}"],
      timeout     => 0,
      path        => ['/opt/uv/bin'],
    }
  }
}
