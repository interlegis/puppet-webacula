# init.pp

class webacula ( $source          = 'https://github.com/tim4dev/webacula.git',
                 $installdir      = '/var/www/webacula',
                 $vhostname       = $fqdn,
                 $dbhost          = 'localhost',
                 $dbname          = 'bacula',
                 $dbuser          = 'webacula',
                 $dbpass          = 'webacula',
                 $root_pass_hash  = 'webacula',
             ) {

  if $dbhost == 'localhost' {
    class { 'webacula::database::mysql':
      ensure        => 'present',
      host          => 'localhost',
      password_hash => mysql_password("${dbpass}"),
      user          => $dbuser, 
      dbname        => $dbname, 
    }
  }

  if !defined(Class['apache']) {
    class { 'apache':
      mpm_module        => 'prefork',
      keepalive         => 'off',
      keepalive_timeout => '4',
      timeout           => '45',
      default_vhost     => false,
    }
  }
  if !defined(Class['apache::mod::php']) {
    include apache::mod::php
  }
  if !defined(Class['apache::mod::rewrite']) {
    include apache::mod::rewrite
  }

  Exec { path => ["/bin", "/usr/bin", "/usr/sbin", "/usr/local/bin"] }

  exec { "create installdir":
    command => "mkdir -p $installdir",
    unless  => "test -d $installdir",
  }

  file { "$installdir":
    ensure => directory,
    owner => 'www-data', group => 'root', mode => '664',
    recurse => true,
    require => Exec['create installdir'],
  }

  ensure_packages ( 'git' )

  vcsrepo { "${installdir}":
    ensure   => present,
    provider => git,
    source   => $source,
    require  => Package['git'],
  }  

  # Vhost
  apache::vhost { $vhostname:
    port => '80',
    docroot => "$installdir/html",
    access_log_file => 'access_webacula.log',
    error_log_file => 'error_webacula.log',
    setenv  => 'APPLICATION_ENV production',
    aliases => [ { alias => '/webacula',
                   path  => "${installdir}/html" }
               ],
    directories => [
      { path      => "${installdir}/html",
        rewrites  => [
          { rewrite_base => '/webacula',
            rewrite_cond => [ '%{REQUEST_FILENAME} -s',
                              '%{REQUEST_FILENAME} -l',
                              '%{REQUEST_FILENAME} -d' ],
            rewrite_rule => [ '^.*$ - [NC,L]',
                              '^.*$ index.php [NC,L]' ],
          }
        ],
        custom_fragment => 'php_flag magic_quotes_gpc off
    php_flag register_globals off',
        options        => ['Indexes', 'FollowSymLinks'],
        allow_override => 'All',
        order          => 'deny, allow',
        deny           => 'from all',
        allow          => ['from 127.0.0.1', 'from localhost', 'from ::1', 'from 10.1.0.0/16' ],
      },
      { path  => "${installdir}/docs",
        order => 'deny, allow',
        deny  => 'from all',
      }, 
      { path  => "${installdir}/application",
        order => 'deny, allow',
        deny  => 'from all',
      }, 
      { path  => "${installdir}/languages",
        order => 'deny, allow',
        deny  => 'from all',
      }, 
      { path  => "${installdir}/library",
        order => 'deny, allow',
        deny  => 'from all',
      }, 
      { path  => "${installdir}/install",
        order => 'deny, allow',
        deny  => 'from all',
      }, 
      { path  => "${installdir}/tests",
        order => 'deny, allow',
        deny  => 'from all',
      }, 
      { path  => "${installdir}/data",
        order => 'deny, allow',
        deny  => 'from all',
      }, 
    ]
  }

  # Prereqs
  $pkgs = [ 'php5', 
            'bacula-server', 
            'bacula-console', 
            'bacula-director-mysql', 
            'zend-framework' ]
  ensure_packages ( $pkgs , { notify => Exec['make_tables'] })

  # PHP Cache Config
  php::module { [ 'mysql', 'gd' ]: }

  
  #Configs
  augeas { "${installdir}/application/config.ini":
    changes => [
      "set db.config.username \"${dbuser}\"",
      "set db.config.password \"${dbpass}\"",
      'set def.timezone "America/Sao_Paulo"',
      'set bacula.sudo "/usr/bin/sudo"',
      'set bacula.bconsole "/usr/sbin/bconsole"',
      'set bacula.bconsolecmd "-n -c /etc/bacula/bconsole.conf"',
    ],
    lens => 'PHP.lns',
    incl => "${installdir}/application/config.ini",
    context => "/files/${installdir}/application/config.ini/general",
    notify => Exec['make_tables'],
  } 

  file { "${installdir}/install/db.conf":
    content => "db_name=\"${dbname}\"
db_pwd=\"${dbpass}\"
db_user=\"${dbuser}\"
webacula_root_pwd=\"${root_pass_hash}\"
",
  }

  file { "${installdir}/library/Zend":
    ensure => link,
    target => '/usr/share/php/libzend-framework-php/Zend'
  }

  augeas { "/etc/php5/apache2/php.ini":
    changes => [
     "set memory_limit 128M",
     "set max_execution_time 3600",
    ],
    context => "/files/etc/php5/apache2/php.ini/PHP",
  } 

  exec { 'make_tables':
    command     => "bash ${installdir}/install/MySql/10_make_tables.sh",
    refreshonly => true,
    notify      => Exec['acl_make_tables'],
    require     => [ File["${installdir}/install/db.conf"],
                     Augeas["${installdir}/application/config.ini"],
                     Class['webacula::database::mysql'],
                     Package['bacula-director-mysql'],
                   ],
  }

  exec { 'acl_make_tables':
    command     => "bash ${installdir}/install/MySql/10_make_tables.sh",
    refreshonly => true,
    require     => Exec['make_tables'],
  }

  
  # Configure sudoers for bconsole
  if !defined( Class['sudo'] ) {
    class { 'sudo':
      purge               => false,
      config_file_replace => false,
    }
  }
  sudo::conf { 'bconsole':
    content => 'www-data ALL=(root) NOPASSWD:/usr/sbin/bconsole',
  }
}
