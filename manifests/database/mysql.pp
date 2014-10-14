#mysql.pp

class webacula::database::mysql (  $ensure = 'present',
                                   $host = 'localhost',
                                   $password_hash = mysql_password('webacula'),
                                   $user = 'webacula',
                                   $dbname = 'bacula',
                             ) {

  include webacula::database::mysql_server

  mysql_user { "${user}@${host}":
    ensure => $ensure,
    password_hash => $password_hash,
  }
  mysql_grant { "${user}@${host}/${dbname}.*":
    ensure => $ensure,
    options => ['GRANT'],
    privileges => ['ALL'],
    table => "${dbname}.*",
    user => "${user}@${host}",
  }
}

