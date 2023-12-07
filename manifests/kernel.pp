# 
class jupyterhub::kernel::venv (
  Stdlib::Absolutepath $python,
  Stdlib::Absolutepath $prefix = '/opt/ipython-kernel',
  Array[String] $packages = [],
  Hash $pip_environment = {}
) {
  $pip_version = lookup('jupyterhub::pip::version')

  exec { 'kernel_venv':
    command => "${python} -m venv --system-site-packages ${prefix}",
    creates => "${prefix}/bin/python",
  }

  exec { 'upgrade_pip_setuptools':
    command     => "pip install --prefix ${prefix} --no-cache-dir --upgrade pip==${pip_version} setuptools",
    subscribe   => Exec['kernel_venv'],
    refreshonly => true,
    path        => ["${prefix}/bin"],
  }

  exec { 'pip_ipykernel':
    command => 'pip install --no-cache-dir ipykernel',
    creates => "${prefix}/bin/ipython",
    require => Exec['kernel_venv'],
    path    => ["${prefix}/bin"],
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

  exec { 'install_kernel':
    command => "python -m ipykernel install --name python3 --prefix ${::jupyterhub::node::prefix}",
    creates => "${::jupyterhub::node::prefix}/share/jupyter/kernels/python3/kernel.json",
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
      command     => "pip install --no-deps --no-cache-dir --prefix ${prefix} --upgrade -r ${prefix}/kernel-requirements.txt",
      subscribe   => File["${prefix}/hub-requirements.txt"],
      refreshonly => true,
      environment => $pip_env_list,
      timeout     => 0,
      path        => ["${prefix}/bin"],
    }

    exec { 'install_kernel_requirements_deps':
      command     => "pip install --no-cache-dir --prefix ${prefix} --upgrade -r ${prefix}/kernel-requirements.txt",
      subscribe   => Exec['install_kernel_requirements_nodeps'],
      refreshonly => true,
      environment => $pip_env_list,
      timeout     => 0,
      path        => ["${prefix}/bin"],
    }
  }
}
