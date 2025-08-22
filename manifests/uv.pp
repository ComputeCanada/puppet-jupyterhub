class jupyterhub::uv::install (
  String $prefix,
  String $version,
) {
  ensure_resource('file', $prefix, { 'ensure' => 'directory' })
  ensure_resource('file', "${prefix}/bin", { 'ensure' => 'directory', require => File[$prefix] })
  $arch = $::facts['os']['architecture']
  archive { 'jh_install_uv':
    path            => '/tmp/uv',
    source          => "https://github.com/astral-sh/uv/releases/download/${version}/uv-${arch}-unknown-linux-gnu.tar.gz",
    extract         => true,
    extract_path    => "${prefix}/bin",
    extract_command => 'tar xfz %s --strip-components=1',
    creates         => "${$prefix}/bin/uv",
    cleanup         => true,
    require         => File["${prefix}/bin"],
  }
}

define jupyterhub::uv::venv (
  String $prefix,
  Variant[Stdlib::Absolutepath, String] $python,
  String $requirements,
  Hash[String, Variant[String, Integer, Array[String]]] $pip_environment = {},
) {
  $uv_prefix = lookup('jupyterhub::uv::install::prefix')

  $pip_env_list = $pip_environment.reduce([]) |Array $list, Array $value| {
    if $value[1] =~ Stdlib::Compat::Array {
      $concat = $value[1].reduce('') | String $concat, String $token | {
        "${token}:${concat}"
      }
      $list + ["${value[0]}=${concat}"]
    }
    else {
      $list + ["${value[0]}=${value[1]}"]
    }
  }

  if $python =~ Stdlib::Absolutepath {
    $path    = ["${uv_prefix}/bin", dirname($python),'/bin', '/usr/bin']
    $environ = []
  } else {
    $path    = ["${uv_prefix}/bin"]
    $environ = ["XDG_DATA_HOME=${uv_prefix}/share"]
  }

  exec { "${name}_venv":
    command     => "uv venv --seed -p ${python} ${prefix}",
    creates     => "${prefix}/bin/python",
    require     => Class['jupyterhub::uv::install'],
    path        => $path,
    environment => $environ,
  }

  file { "${prefix}/${name}-requirements.txt":
    content => $requirements,
  }

  if 'PIP_CONFIG_FILE' in $pip_environment {
    $pip_cmd = "pip install -r ${prefix}/${name}-requirements.txt"
    $pip_environ = $pip_env_list
    $pip_path = ["${prefix}/bin"]
  } else {
    $pip_cmd = "uv pip install -r ${prefix}/${name}-requirements.txt"
    $pip_environ = $pip_env_list + ["VIRTUAL_ENV=${prefix}"]
    $pip_path = ["${uv_prefix}/bin"]
  }
  exec { "${name}_pip_install":
    command     => $pip_cmd,
    subscribe   => File["${prefix}/${name}-requirements.txt"],
    refreshonly => true,
    environment => $pip_environ,
    timeout     => 0,
    path        => $pip_path,
    require     => Exec["${name}_venv"],
  }
}
