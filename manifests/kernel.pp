# 
class jupyterhub::kernel::venv (
  Variant[Stdlib::Absolutepath, String] $python,
  Stdlib::Absolutepath $prefix = '/opt/ipython-kernel',
  String $kernel_name = 'python3',
  String $display_name = 'Python 3',
  Array[String] $packages = [],
  Hash[String, Variant[String, Integer, Array[String]]] $pip_environment = {},
  Hash $kernel_environment = {}
) {
  if $python =~ Stdlib::Absolutepath {
    exec { 'kernel_venv':
      command => "uv venv --seed --python ${python} ${prefix}",
      creates => "${prefix}/bin/python",
      require => Archive['jh_install_uv'],
      path    => [
        '/opt/uv/bin',
        dirname($python),
        '/bin',
        '/usr/bin',
      ],
    }
  } else {
    exec { 'kernel_venv':
      command     => "uv venv --seed -p ${python} ${prefix}",
      creates     => "${prefix}/bin/python",
      require     => Archive['jh_install_uv'],
      path        => ['/opt/uv/bin'],
      environment => ['XDG_DATA_HOME=/opt/uv/share'],
    }
  }

  exec { 'pip_ipykernel':
    command     => 'uv pip install ipykernel',
    creates     => "${prefix}/bin/ipython",
    require     => Exec['kernel_venv'],
    environment => ["VIRTUAL_ENV=${prefix}"],
    path        => ['/opt/uv/bin'],
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

  ensure_resource('file', "${prefix}/puppet-jupyter", { 'ensure' => 'directory', require => Exec['kernel_venv']})
  ensure_resource('file', "${prefix}/puppet-jupyter/kernels", { 'ensure' => 'directory', require => File["${prefix}/puppet-jupyter"] })
  ensure_resource('file', "${prefix}/puppet-jupyter/kernels/${kernel_name}", { 'ensure' => 'directory', require => File["${prefix}/puppet-jupyter/kernels"] })
  file { "${prefix}/puppet-jupyter/kernels/${kernel_name}/kernel.json":
    content => epp('jupyterhub/kernel.json', { 'prefix' => $prefix, 'display_name' => $display_name, 'env' => $kernel_environment }),
    require => File["${prefix}/puppet-jupyter/kernels/${kernel_name}"],
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
  }

  file { "${prefix}/puppet-jupyter/kernels/${kernel_name}/logo-svg.svg":
    source  => "file://${prefix}/share/jupyter/kernels/python3/logo-svg.svg",
    require => [
      File["${prefix}/puppet-jupyter/kernels/${kernel_name}"],
      Exec['pip_ipykernel'],
    ],
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
  }

  if (!$packages.empty) {
    $pip_env_list = $pip_environment.reduce([]) |Array $list, Array $value| {
      if $value[1] =~ Stdlib::Compat::Array {
        $concat = $value[1].reduce("") | String $concat, String $token | {
          "${token}:${concat}"
        }
        $list + ["${value[0]}=${concat}"]
      }
      else {
        $list + ["${value[0]}=${value[1]}"]
      }
    }

    $pkg_string = join($packages, "\n")

    file { "${prefix}/kernel-requirements.txt":
      content => $pkg_string,
    }

    if 'PIP_CONFIG_FILE' in $pip_environment {
      exec { 'install_kernel_requirements_nodeps':
        command     => "pip --no-cache-dir install -r ${prefix}/kernel-requirements.txt",
        subscribe   => File["${prefix}/kernel-requirements.txt"],
        refreshonly => true,
        environment => $pip_env_list,
        timeout     => 0,
        path        => ["${prefix}/bin"],
      }
    } else {
      exec { 'install_kernel_requirements_nodeps':
        command     => "uv --no-cache pip install -r ${prefix}/kernel-requirements.txt",
        subscribe   => File["${prefix}/kernel-requirements.txt"],
        refreshonly => true,
        environment => $pip_env_list + ["VIRTUAL_ENV=${prefix}"],
        timeout     => 0,
        path        => ['/opt/uv/bin'],
      }
    }
  }
}
