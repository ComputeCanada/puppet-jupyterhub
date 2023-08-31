class jupyterhub::kernel::venv(
  Stdlib::Absolutepath $python = '/usr/bin/python3',
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
    command     => "${prefix}/bin/pip install --no-cache-dir --upgrade pip==${pip_version} setuptools",
    subscribe   => Exec['kernel_venv'],
    refreshonly => true,
  }

  exec { 'pip_ipykernel':
    command => "${prefix}/bin/pip install --no-cache-dir ipykernel",
    creates => "${prefix}/bin/ipython",
    require => Exec['kernel_venv']
  }

  exec { 'install_kernel':
    command => "${prefix}/bin/python -m ipykernel install --name python3 --prefix ${::jupyterhub::node::prefix}",
    creates => "${::jupyterhub::node::prefix}/share/jupyter/kernels/python3/kernel.json",
    require => [Exec['pip_ipykernel']]
  }

  if (!$packages.empty) {
    $pip_env_list = $pip_environment.reduce([]) |Array $list, Array $value| {
      $list + ["${value[0]}=${value[1]}"]
    }

    $pkg_string = join($packages, "\n")

    file { "${prefix}/hub-requirements.txt":
      ensure  => present,
      content => $pkg_string,
    }

    exec { 'install_kernel_requirements_nodeps':
      command     => "${prefix}/bin/pip install --no-deps --no-cache-dir --prefix ${prefix} --upgrade -r ${prefix}/hub-requirements.txt",
      subscribe   => File["${prefix}/hub-requirements.txt"],
      refreshonly => true,
      environment => $pip_env_list,
      timeout     => 0,
    }

    exec { 'install_kernel_requirements_deps':
      command     => "${prefix}/bin/pip install --no-cache-dir --prefix ${prefix} --upgrade -r ${prefix}/hub-requirements.txt",
      subscribe   => Exec['install_kernel_requirements_nodeps'],
      refreshonly => true,
      environment => $pip_env_list,
      timeout     => 0,
    }
  }
}
