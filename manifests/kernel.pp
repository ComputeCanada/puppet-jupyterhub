# 
class jupyterhub::kernel (
  Enum['none', 'venv'] $install_method = 'venv',
  Optional[Enum['venv', 'module']] $setup = undef,
) {
  if $setup {
    deprecation('jupyterhub::kernel::setup', 'jupyterhub::kernel::setup is deprecated, use jupyterhub::kernel::install_method instead')
    if $setup == 'venv' {
      include jupyterhub::kernel::venv
    }
  } elsif $install_method == 'venv' {
    include jupyterhub::kernel::venv
  }
}

class jupyterhub::kernel::venv (
  Stdlib::Absolutepath $prefix,
  Variant[Stdlib::Absolutepath, String] $python,
  String $kernel_name = 'python3',
  String $display_name = 'Python 3',
  Array[String] $packages = [],
  Hash[String, Variant[String, Integer, Array[String]]] $pip_environment = {},
  Hash $kernel_environment = {}
) {
  include jupyterhub::uv::install

  jupyterhub::uv::venv { 'kernel':
    prefix          => $prefix,
    python          => $python,
    requirements    => join(['ipykernel'] + $packages, "\n"),
    pip_environment => $pip_environment,
  }

  file { "${prefix}/etc":
    ensure  => directory,
    require => Jupyterhub::Uv::Venv['kernel'],
  }

  file { "${prefix}/etc/ipython":
    ensure  => directory,
    require => File["${prefix}/etc"],
  }

  file { "${prefix}/share/jupyter/kernels/python3/kernel.json":
    ensure  => absent,
    require => Jupyterhub::Uv::Venv['kernel'],
  }

  file { "${prefix}/etc/ipython/ipython_config.py":
    source => 'puppet:///modules/jupyterhub/ipython_config.py',
  }

  ensure_resource('file', "${prefix}/puppet-jupyter", { 'ensure' => 'directory', require => Jupyterhub::Uv::Venv['kernel'] })
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
      Jupyterhub::Uv::Venv['kernel'],
    ],
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
  }
}
