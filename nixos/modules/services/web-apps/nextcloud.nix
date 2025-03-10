{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nextcloud;
  fpm = config.services.phpfpm.pools.nextcloud;

  inherit (cfg) datadir;

  phpPackage = cfg.phpPackage.buildEnv {
    extensions = { enabled, all }:
      (with all;
        enabled
        ++ optional cfg.enableImagemagick imagick
        # Optionally enabled depending on caching settings
        ++ optional cfg.caching.apcu apcu
        ++ optional cfg.caching.redis redis
        ++ optional cfg.caching.memcached memcached
      )
      ++ cfg.phpExtraExtensions all; # Enabled by user
    extraConfig = toKeyValue phpOptions;
  };

  toKeyValue = generators.toKeyValue {
    mkKeyValue = generators.mkKeyValueDefault {} " = ";
  };

  phpOptions = {
    upload_max_filesize = cfg.maxUploadSize;
    post_max_size = cfg.maxUploadSize;
    memory_limit = cfg.maxUploadSize;
  } // cfg.phpOptions
    // optionalAttrs cfg.caching.apcu {
      "apc.enable_cli" = "1";
    };

  occ = pkgs.writeScriptBin "nextcloud-occ" ''
    #! ${pkgs.runtimeShell}
    cd ${cfg.package}
    sudo=exec
    if [[ "$USER" != nextcloud ]]; then
      sudo='exec /run/wrappers/bin/sudo -u nextcloud --preserve-env=NEXTCLOUD_CONFIG_DIR --preserve-env=OC_PASS'
    fi
    export NEXTCLOUD_CONFIG_DIR="${datadir}/config"
    $sudo \
      ${phpPackage}/bin/php \
      occ "$@"
  '';

  inherit (config.system) stateVersion;

in {

  imports = [
    (mkRemovedOptionModule [ "services" "nextcloud" "config" "adminpass" ] ''
      Please use `services.nextcloud.config.adminpassFile' instead!
    '')
    (mkRemovedOptionModule [ "services" "nextcloud" "config" "dbpass" ] ''
      Please use `services.nextcloud.config.dbpassFile' instead!
    '')
    (mkRemovedOptionModule [ "services" "nextcloud" "nginx" "enable" ] ''
      The nextcloud module supports `nginx` as reverse-proxy by default and doesn't
      support other reverse-proxies officially.

      However it's possible to use an alternative reverse-proxy by

        * disabling nginx
        * setting `listen.owner` & `listen.group` in the phpfpm-pool to a different value

      Further details about this can be found in the `Nextcloud`-section of the NixOS-manual
      (which can be openend e.g. by running `nixos-help`).
    '')
    (mkRemovedOptionModule [ "services" "nextcloud" "disableImagemagick" ] ''
      Use services.nextcloud.nginx.enableImagemagick instead.
    '')
  ];

  options.services.nextcloud = {
    enable = mkEnableOption "nextcloud";
    hostName = mkOption {
      type = types.str;
      description = "FQDN for the nextcloud instance.";
    };
    home = mkOption {
      type = types.str;
      default = "/var/lib/nextcloud";
      description = "Storage path of nextcloud.";
    };
    datadir = mkOption {
      type = types.str;
      defaultText = "config.services.nextcloud.home";
      description = ''
        Data storage path of nextcloud.  Will be <xref linkend="opt-services.nextcloud.home" /> by default.
        This folder will be populated with a config.php and data folder which contains the state of the instance (excl the database).";
      '';
      example = "/mnt/nextcloud-file";
    };
    extraApps = mkOption {
      type = types.attrsOf types.package;
      default = { };
      description = ''
        Extra apps to install. Should be an attrSet of appid to packages generated by fetchNextcloudApp.
        The appid must be identical to the "id" value in the apps appinfo/info.xml.
        Using this will disable the appstore to prevent Nextcloud from updating these apps (see <xref linkend="opt-services.nextcloud.appstoreEnable" />).
      '';
      example = literalExpression ''
        {
          maps = pkgs.fetchNextcloudApp {
            name = "maps";
            sha256 = "007y80idqg6b6zk6kjxg4vgw0z8fsxs9lajnv49vv1zjy6jx2i1i";
            url = "https://github.com/nextcloud/maps/releases/download/v0.1.9/maps-0.1.9.tar.gz";
            version = "0.1.9";
          };
          phonetrack = pkgs.fetchNextcloudApp {
            name = "phonetrack";
            sha256 = "0qf366vbahyl27p9mshfma1as4nvql6w75zy2zk5xwwbp343vsbc";
            url = "https://gitlab.com/eneiluj/phonetrack-oc/-/wikis/uploads/931aaaf8dca24bf31a7e169a83c17235/phonetrack-0.6.9.tar.gz";
            version = "0.6.9";
          };
        }
        '';
    };
    extraAppsEnable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Automatically enable the apps in <xref linkend="opt-services.nextcloud.extraApps" /> every time nextcloud starts.
        If set to false, apps need to be enabled in the Nextcloud user interface or with nextcloud-occ app:enable.
      '';
    };
    appstoreEnable = mkOption {
      type = types.nullOr types.bool;
      default = null;
      example = true;
      description = ''
        Allow the installation of apps and app updates from the store.
        Enabled by default unless there are packages in <xref linkend="opt-services.nextcloud.extraApps" />.
        Set to true to force enable the store even if <xref linkend="opt-services.nextcloud.extraApps" /> is used.
        Set to false to disable the installation of apps from the global appstore. App management is always enabled regardless of this setting.
      '';
    };
    logLevel = mkOption {
      type = types.ints.between 0 4;
      default = 2;
      description = "Log level value between 0 (DEBUG) and 4 (FATAL).";
    };
    https = mkOption {
      type = types.bool;
      default = false;
      description = "Use https for generated links.";
    };
    package = mkOption {
      type = types.package;
      description = "Which package to use for the Nextcloud instance.";
      relatedPackages = [ "nextcloud22" "nextcloud23" "nextcloud24" ];
    };
    phpPackage = mkOption {
      type = types.package;
      relatedPackages = [ "php74" "php80" "php81" ];
      defaultText = "pkgs.php";
      description = ''
        PHP package to use for Nextcloud.
      '';
    };

    maxUploadSize = mkOption {
      default = "512M";
      type = types.str;
      description = ''
        Defines the upload limit for files. This changes the relevant options
        in php.ini and nginx if enabled.
      '';
    };

    skeletonDirectory = mkOption {
      default = "";
      type = types.str;
      description = ''
        The directory where the skeleton files are located. These files will be
        copied to the data directory of new users. Leave empty to not copy any
        skeleton files.
      '';
    };

    webfinger = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable this option if you plan on using the webfinger plugin.
        The appropriate nginx rewrite rules will be added to your configuration.
      '';
    };

    phpExtraExtensions = mkOption {
      type = with types; functionTo (listOf package);
      default = all: [];
      defaultText = literalExpression "all: []";
      description = ''
        Additional PHP extensions to use for nextcloud.
        By default, only extensions necessary for a vanilla nextcloud installation are enabled,
        but you may choose from the list of available extensions and add further ones.
        This is sometimes necessary to be able to install a certain nextcloud app that has additional requirements.
      '';
      example = literalExpression ''
        all: [ all.pdlib all.bz2 ]
      '';
    };

    phpOptions = mkOption {
      type = types.attrsOf types.str;
      default = {
        short_open_tag = "Off";
        expose_php = "Off";
        error_reporting = "E_ALL & ~E_DEPRECATED & ~E_STRICT";
        display_errors = "stderr";
        "opcache.enable_cli" = "1";
        "opcache.interned_strings_buffer" = "8";
        "opcache.max_accelerated_files" = "10000";
        "opcache.memory_consumption" = "128";
        "opcache.revalidate_freq" = "1";
        "opcache.fast_shutdown" = "1";
        "openssl.cafile" = "/etc/ssl/certs/ca-certificates.crt";
        catch_workers_output = "yes";
      };
      description = ''
        Options for PHP's php.ini file for nextcloud.
      '';
    };

    poolSettings = mkOption {
      type = with types; attrsOf (oneOf [ str int bool ]);
      default = {
        "pm" = "dynamic";
        "pm.max_children" = "32";
        "pm.start_servers" = "2";
        "pm.min_spare_servers" = "2";
        "pm.max_spare_servers" = "4";
        "pm.max_requests" = "500";
      };
      description = ''
        Options for nextcloud's PHP pool. See the documentation on <literal>php-fpm.conf</literal> for details on configuration directives.
      '';
    };

    poolConfig = mkOption {
      type = types.nullOr types.lines;
      default = null;
      description = ''
        Options for nextcloud's PHP pool. See the documentation on <literal>php-fpm.conf</literal> for details on configuration directives.
      '';
    };

    database = {

      createLocally = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Create the database and database user locally. Only available for
          mysql database.
          Note that this option will use the latest version of MariaDB which
          is not officially supported by Nextcloud. As for now a workaround
          is used to also support MariaDB version >= 10.6.
        '';
      };

    };


    config = {
      dbtype = mkOption {
        type = types.enum [ "sqlite" "pgsql" "mysql" ];
        default = "sqlite";
        description = "Database type.";
      };
      dbname = mkOption {
        type = types.nullOr types.str;
        default = "nextcloud";
        description = "Database name.";
      };
      dbuser = mkOption {
        type = types.nullOr types.str;
        default = "nextcloud";
        description = "Database user.";
      };
      dbpassFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The full path to a file that contains the database password.
        '';
      };
      dbhost = mkOption {
        type = types.nullOr types.str;
        default = "localhost";
        description = ''
          Database host.

          Note: for using Unix authentication with PostgreSQL, this should be
          set to <literal>/run/postgresql</literal>.
        '';
      };
      dbport = mkOption {
        type = with types; nullOr (either int str);
        default = null;
        description = "Database port.";
      };
      dbtableprefix = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Table prefix in Nextcloud database.";
      };
      adminuser = mkOption {
        type = types.str;
        default = "root";
        description = "Admin username.";
      };
      adminpassFile = mkOption {
        type = types.str;
        description = ''
          The full path to a file that contains the admin's password. Must be
          readable by user <literal>nextcloud</literal>.
        '';
      };

      extraTrustedDomains = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Trusted domains, from which the nextcloud installation will be
          acessible.  You don't need to add
          <literal>services.nextcloud.hostname</literal> here.
        '';
      };

      trustedProxies = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Trusted proxies, to provide if the nextcloud installation is being
          proxied to secure against e.g. spoofing.
        '';
      };

      overwriteProtocol = mkOption {
        type = types.nullOr (types.enum [ "http" "https" ]);
        default = null;
        example = "https";

        description = ''
          Force Nextcloud to always use HTTPS i.e. for link generation. Nextcloud
          uses the currently used protocol by default, but when behind a reverse-proxy,
          it may use <literal>http</literal> for everything although Nextcloud
          may be served via HTTPS.
        '';
      };

      defaultPhoneRegion = mkOption {
        default = null;
        type = types.nullOr types.str;
        example = "DE";
        description = ''
          <warning>
           <para>This option exists since Nextcloud 21! If older versions are used,
            this will throw an eval-error!</para>
          </warning>

          <link xlink:href="https://www.iso.org/iso-3166-country-codes.html">ISO 3611-1</link>
          country codes for automatic phone-number detection without a country code.

          With e.g. <literal>DE</literal> set, the <literal>+49</literal> can be omitted for
          phone-numbers.
        '';
      };

      objectstore = {
        s3 = {
          enable = mkEnableOption ''
            S3 object storage as primary storage.

            This mounts a bucket on an Amazon S3 object storage or compatible
            implementation into the virtual filesystem.

            Further details about this feature can be found in the
            <link xlink:href="https://docs.nextcloud.com/server/22/admin_manual/configuration_files/primary_storage.html">upstream documentation</link>.
          '';
          bucket = mkOption {
            type = types.str;
            example = "nextcloud";
            description = ''
              The name of the S3 bucket.
            '';
          };
          autocreate = mkOption {
            type = types.bool;
            description = ''
              Create the objectstore if it does not exist.
            '';
          };
          key = mkOption {
            type = types.str;
            example = "EJ39ITYZEUH5BGWDRUFY";
            description = ''
              The access key for the S3 bucket.
            '';
          };
          secretFile = mkOption {
            type = types.str;
            example = "/var/nextcloud-objectstore-s3-secret";
            description = ''
              The full path to a file that contains the access secret. Must be
              readable by user <literal>nextcloud</literal>.
            '';
          };
          hostname = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "example.com";
            description = ''
              Required for some non-Amazon implementations.
            '';
          };
          port = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = ''
              Required for some non-Amazon implementations.
            '';
          };
          useSsl = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Use SSL for objectstore access.
            '';
          };
          region = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "REGION";
            description = ''
              Required for some non-Amazon implementations.
            '';
          };
          usePathStyle = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Required for some non-Amazon S3 implementations.

              Ordinarily, requests will be made with
              <literal>http://bucket.hostname.domain/</literal>, but with path style
              enabled requests are made with
              <literal>http://hostname.domain/bucket</literal> instead.
            '';
          };
        };
      };
    };

    enableImagemagick = mkEnableOption ''
        the ImageMagick module for PHP.
        This is used by the theming app and for generating previews of certain images (e.g. SVG and HEIF).
        You may want to disable it for increased security. In that case, previews will still be available
        for some images (e.g. JPEG and PNG).
        See <link xlink:href="https://github.com/nextcloud/server/issues/13099" />.
    '' // {
      default = true;
    };

    caching = {
      apcu = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to load the APCu module into PHP.
        '';
      };
      redis = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to load the Redis module into PHP.
          You still need to enable Redis in your config.php.
          See https://docs.nextcloud.com/server/14/admin_manual/configuration_server/caching_configuration.html
        '';
      };
      memcached = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to load the Memcached module into PHP.
          You still need to enable Memcached in your config.php.
          See https://docs.nextcloud.com/server/14/admin_manual/configuration_server/caching_configuration.html
        '';
      };
    };
    autoUpdateApps = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Run regular auto update of all apps installed from the nextcloud app store.
        '';
      };
      startAt = mkOption {
        type = with types; either str (listOf str);
        default = "05:00:00";
        example = "Sun 14:00:00";
        description = ''
          When to run the update. See `systemd.services.&lt;name&gt;.startAt`.
        '';
      };
    };
    occ = mkOption {
      type = types.package;
      default = occ;
      defaultText = literalDocBook "generated script";
      internal = true;
      description = ''
        The nextcloud-occ program preconfigured to target this Nextcloud instance.
      '';
    };
    globalProfiles = mkEnableOption "global profiles" // {
      description = ''
        Makes user-profiles globally available under <literal>nextcloud.tld/u/user.name</literal>.
        Even though it's enabled by default in Nextcloud, it must be explicitly enabled
        here because it has the side-effect that personal information is even accessible to
        unauthenticated users by default.

        By default, the following properties are set to <quote>Show to everyone</quote>
        if this flag is enabled:
        <itemizedlist>
        <listitem><para>About</para></listitem>
        <listitem><para>Full name</para></listitem>
        <listitem><para>Headline</para></listitem>
        <listitem><para>Organisation</para></listitem>
        <listitem><para>Profile picture</para></listitem>
        <listitem><para>Role</para></listitem>
        <listitem><para>Twitter</para></listitem>
        <listitem><para>Website</para></listitem>
        </itemizedlist>

        Only has an effect in Nextcloud 23 and later.
      '';
    };

    nginx = {
      recommendedHttpHeaders = mkOption {
        type = types.bool;
        default = true;
        description = "Enable additional recommended HTTP response headers";
      };
      hstsMaxAge = mkOption {
        type = types.ints.positive;
        default = 15552000;
        description = ''
          Value for the <code>max-age</code> directive of the HTTP
          <code>Strict-Transport-Security</code> header.

          See section 6.1.1 of IETF RFC 6797 for detailed information on this
          directive and header.
        '';
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    { warnings = let
        latest = 24;
        upgradeWarning = major: nixos:
          ''
            A legacy Nextcloud install (from before NixOS ${nixos}) may be installed.

            After nextcloud${toString major} is installed successfully, you can safely upgrade
            to ${toString (major + 1)}. The latest version available is nextcloud${toString latest}.

            Please note that Nextcloud doesn't support upgrades across multiple major versions
            (i.e. an upgrade from 16 is possible to 17, but not 16 to 18).

            The package can be upgraded by explicitly declaring the service-option
            `services.nextcloud.package`.
          '';

        # FIXME(@Ma27) remove as soon as nextcloud properly supports
        # mariadb >=10.6.
        isUnsupportedMariadb =
          # All currently supported Nextcloud versions are affected (https://github.com/nextcloud/server/issues/25436).
          (versionOlder cfg.package.version "24")
          # This module uses mysql
          && (cfg.config.dbtype == "mysql")
          # MySQL is managed via NixOS
          && config.services.mysql.enable
          # We're using MariaDB
          && (getName config.services.mysql.package) == "mariadb-server"
          # MariaDB is at least 10.6 and thus not supported
          && (versionAtLeast (getVersion config.services.mysql.package) "10.6");

      in (optional (cfg.poolConfig != null) ''
          Using config.services.nextcloud.poolConfig is deprecated and will become unsupported in a future release.
          Please migrate your configuration to config.services.nextcloud.poolSettings.
        '')
        ++ (optional (versionOlder cfg.package.version "21") (upgradeWarning 20 "21.05"))
        ++ (optional (versionOlder cfg.package.version "22") (upgradeWarning 21 "21.11"))
        ++ (optional (versionOlder cfg.package.version "23") (upgradeWarning 22 "22.05"))
        ++ (optional (versionOlder cfg.package.version "24") (upgradeWarning 23 "22.05"))
        ++ (optional isUnsupportedMariadb ''
            You seem to be using MariaDB at an unsupported version (i.e. at least 10.6)!
            Please note that this isn't supported officially by Nextcloud. You can either

            * Switch to `pkgs.mysql`
            * Downgrade MariaDB to at least 10.5
            * Work around Nextcloud's problems by specifying `innodb_read_only_compressed=0`

            For further context, please read
            https://help.nextcloud.com/t/update-to-next-cloud-21-0-2-has-get-an-error/117028/15
          '');

      services.nextcloud.package = with pkgs;
        mkDefault (
          if pkgs ? nextcloud
            then throw ''
              The `pkgs.nextcloud`-attribute has been removed. If it's supposed to be the default
              nextcloud defined in an overlay, please set `services.nextcloud.package` to
              `pkgs.nextcloud`.
            ''
          else if versionOlder stateVersion "21.11" then nextcloud21
          else if versionOlder stateVersion "22.05" then nextcloud22
          else nextcloud24
        );

      services.nextcloud.datadir = mkOptionDefault config.services.nextcloud.home;

      services.nextcloud.phpPackage =
        if versionOlder cfg.package.version "21" then pkgs.php74
        else if versionOlder cfg.package.version "24" then pkgs.php80
        else pkgs.php81;
    }

    { assertions = [
      { assertion = cfg.database.createLocally -> cfg.config.dbtype == "mysql";
        message = ''services.nextcloud.config.dbtype must be set to mysql if services.nextcloud.database.createLocally is set to true.'';
      }
    ]; }

    { systemd.timers.nextcloud-cron = {
        wantedBy = [ "timers.target" ];
        timerConfig.OnBootSec = "5m";
        timerConfig.OnUnitActiveSec = "5m";
        timerConfig.Unit = "nextcloud-cron.service";
      };

      systemd.tmpfiles.rules = ["d ${cfg.home} 0750 nextcloud nextcloud"];

      systemd.services = {
        # When upgrading the Nextcloud package, Nextcloud can report errors such as
        # "The files of the app [all apps in /var/lib/nextcloud/apps] were not replaced correctly"
        # Restarting phpfpm on Nextcloud package update fixes these issues (but this is a workaround).
        phpfpm-nextcloud.restartTriggers = [ cfg.package ];

        nextcloud-setup = let
          c = cfg.config;
          writePhpArrary = a: "[${concatMapStringsSep "," (val: ''"${toString val}"'') a}]";
          requiresReadSecretFunction = c.dbpassFile != null || c.objectstore.s3.enable;
          objectstoreConfig = let s3 = c.objectstore.s3; in optionalString s3.enable ''
            'objectstore' => [
              'class' => '\\OC\\Files\\ObjectStore\\S3',
              'arguments' => [
                'bucket' => '${s3.bucket}',
                'autocreate' => ${boolToString s3.autocreate},
                'key' => '${s3.key}',
                'secret' => nix_read_secret('${s3.secretFile}'),
                ${optionalString (s3.hostname != null) "'hostname' => '${s3.hostname}',"}
                ${optionalString (s3.port != null) "'port' => ${toString s3.port},"}
                'use_ssl' => ${boolToString s3.useSsl},
                ${optionalString (s3.region != null) "'region' => '${s3.region}',"}
                'use_path_style' => ${boolToString s3.usePathStyle},
              ],
            ]
          '';

          showAppStoreSetting = cfg.appstoreEnable != null || cfg.extraApps != {};
          renderedAppStoreSetting =
            let
              x = cfg.appstoreEnable;
            in
              if x == null then "false"
              else boolToString x;

          nextcloudGreaterOrEqualThan = req: versionAtLeast cfg.package.version req;

          overrideConfig = pkgs.writeText "nextcloud-config.php" ''
            <?php
            ${optionalString requiresReadSecretFunction ''
              function nix_read_secret($file) {
                if (!file_exists($file)) {
                  throw new \RuntimeException(sprintf(
                    "Cannot start Nextcloud, secret file %s set by NixOS doesn't seem to "
                    . "exist! Please make sure that the file exists and has appropriate "
                    . "permissions for user & group 'nextcloud'!",
                    $file
                  ));
                }

                return trim(file_get_contents($file));
              }
            ''}
            $CONFIG = [
              'apps_paths' => [
                ${optionalString (cfg.extraApps != { }) "[ 'path' => '${cfg.home}/nix-apps', 'url' => '/nix-apps', 'writable' => false ],"}
                [ 'path' => '${cfg.home}/apps', 'url' => '/apps', 'writable' => false ],
                [ 'path' => '${cfg.home}/store-apps', 'url' => '/store-apps', 'writable' => true ],
              ],
              ${optionalString (showAppStoreSetting) "'appstoreenabled' => ${renderedAppStoreSetting},"}
              'datadirectory' => '${datadir}/data',
              'skeletondirectory' => '${cfg.skeletonDirectory}',
              ${optionalString cfg.caching.apcu "'memcache.local' => '\\OC\\Memcache\\APCu',"}
              'log_type' => 'syslog',
              'loglevel' => '${builtins.toString cfg.logLevel}',
              ${optionalString (c.overwriteProtocol != null) "'overwriteprotocol' => '${c.overwriteProtocol}',"}
              ${optionalString (c.dbname != null) "'dbname' => '${c.dbname}',"}
              ${optionalString (c.dbhost != null) "'dbhost' => '${c.dbhost}',"}
              ${optionalString (c.dbport != null) "'dbport' => '${toString c.dbport}',"}
              ${optionalString (c.dbuser != null) "'dbuser' => '${c.dbuser}',"}
              ${optionalString (c.dbtableprefix != null) "'dbtableprefix' => '${toString c.dbtableprefix}',"}
              ${optionalString (c.dbpassFile != null) "'dbpassword' => nix_read_secret('${c.dbpassFile}'),"}
              'dbtype' => '${c.dbtype}',
              'trusted_domains' => ${writePhpArrary ([ cfg.hostName ] ++ c.extraTrustedDomains)},
              'trusted_proxies' => ${writePhpArrary (c.trustedProxies)},
              ${optionalString (c.defaultPhoneRegion != null) "'default_phone_region' => '${c.defaultPhoneRegion}',"}
              ${optionalString (nextcloudGreaterOrEqualThan "23") "'profile.enabled' => ${boolToString cfg.globalProfiles}"}
              ${objectstoreConfig}
            ];
          '';
          occInstallCmd = let
            mkExport = { arg, value }: "export ${arg}=${value}";
            dbpass = {
              arg = "DBPASS";
              value = if c.dbpassFile != null
                then ''"$(<"${toString c.dbpassFile}")"''
                else ''""'';
            };
            adminpass = {
              arg = "ADMINPASS";
              value = ''"$(<"${toString c.adminpassFile}")"'';
            };
            installFlags = concatStringsSep " \\\n    "
              (mapAttrsToList (k: v: "${k} ${toString v}") {
              "--database" = ''"${c.dbtype}"'';
              # The following attributes are optional depending on the type of
              # database.  Those that evaluate to null on the left hand side
              # will be omitted.
              ${if c.dbname != null then "--database-name" else null} = ''"${c.dbname}"'';
              ${if c.dbhost != null then "--database-host" else null} = ''"${c.dbhost}"'';
              ${if c.dbport != null then "--database-port" else null} = ''"${toString c.dbport}"'';
              ${if c.dbuser != null then "--database-user" else null} = ''"${c.dbuser}"'';
              "--database-pass" = "\$${dbpass.arg}";
              "--admin-user" = ''"${c.adminuser}"'';
              "--admin-pass" = "\$${adminpass.arg}";
              "--data-dir" = ''"${datadir}/data"'';
            });
          in ''
            ${mkExport dbpass}
            ${mkExport adminpass}
            ${occ}/bin/nextcloud-occ maintenance:install \
                ${installFlags}
          '';
          occSetTrustedDomainsCmd = concatStringsSep "\n" (imap0
            (i: v: ''
              ${occ}/bin/nextcloud-occ config:system:set trusted_domains \
                ${toString i} --value="${toString v}"
            '') ([ cfg.hostName ] ++ cfg.config.extraTrustedDomains));

        in {
          wantedBy = [ "multi-user.target" ];
          before = [ "phpfpm-nextcloud.service" ];
          path = [ occ ];
          script = ''
            ${optionalString (c.dbpassFile != null) ''
              if [ ! -r "${c.dbpassFile}" ]; then
                echo "dbpassFile ${c.dbpassFile} is not readable by nextcloud:nextcloud! Aborting..."
                exit 1
              fi
              if [ -z "$(<${c.dbpassFile})" ]; then
                echo "dbpassFile ${c.dbpassFile} is empty!"
                exit 1
              fi
            ''}
            if [ ! -r "${c.adminpassFile}" ]; then
              echo "adminpassFile ${c.adminpassFile} is not readable by nextcloud:nextcloud! Aborting..."
              exit 1
            fi
            if [ -z "$(<${c.adminpassFile})" ]; then
              echo "adminpassFile ${c.adminpassFile} is empty!"
              exit 1
            fi

            ln -sf ${cfg.package}/apps ${cfg.home}/

            # Install extra apps
            ln -sfT \
              ${pkgs.linkFarm "nix-apps"
                (mapAttrsToList (name: path: { inherit name path; }) cfg.extraApps)} \
              ${cfg.home}/nix-apps

            # create nextcloud directories.
            # if the directories exist already with wrong permissions, we fix that
            for dir in ${datadir}/config ${datadir}/data ${cfg.home}/store-apps ${cfg.home}/nix-apps; do
              if [ ! -e $dir ]; then
                install -o nextcloud -g nextcloud -d $dir
              elif [ $(stat -c "%G" $dir) != "nextcloud" ]; then
                chgrp -R nextcloud $dir
              fi
            done

            ln -sf ${overrideConfig} ${datadir}/config/override.config.php

            # Do not install if already installed
            if [[ ! -e ${datadir}/config/config.php ]]; then
              ${occInstallCmd}
            fi

            ${occ}/bin/nextcloud-occ upgrade

            ${occ}/bin/nextcloud-occ config:system:delete trusted_domains

            ${optionalString (cfg.extraAppsEnable && cfg.extraApps != { }) ''
                # Try to enable apps (don't fail when one of them cannot be enabled , eg. due to incompatible version)
                ${occ}/bin/nextcloud-occ app:enable ${concatStringsSep " " (attrNames cfg.extraApps)}
            ''}

            ${occSetTrustedDomainsCmd}
          '';
          serviceConfig.Type = "oneshot";
          serviceConfig.User = "nextcloud";
        };
        nextcloud-cron = {
          environment.NEXTCLOUD_CONFIG_DIR = "${datadir}/config";
          serviceConfig.Type = "oneshot";
          serviceConfig.User = "nextcloud";
          serviceConfig.ExecStart = "${phpPackage}/bin/php -f ${cfg.package}/cron.php";
        };
        nextcloud-update-plugins = mkIf cfg.autoUpdateApps.enable {
          serviceConfig.Type = "oneshot";
          serviceConfig.ExecStart = "${occ}/bin/nextcloud-occ app:update --all";
          serviceConfig.User = "nextcloud";
          startAt = cfg.autoUpdateApps.startAt;
        };
      };

      services.phpfpm = {
        pools.nextcloud = {
          user = "nextcloud";
          group = "nextcloud";
          phpPackage = phpPackage;
          phpEnv = {
            NEXTCLOUD_CONFIG_DIR = "${datadir}/config";
            PATH = "/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin";
          };
          settings = mapAttrs (name: mkDefault) {
            "listen.owner" = config.services.nginx.user;
            "listen.group" = config.services.nginx.group;
          } // cfg.poolSettings;
          extraConfig = cfg.poolConfig;
        };
      };

      users.users.nextcloud = {
        home = "${cfg.home}";
        group = "nextcloud";
        isSystemUser = true;
      };
      users.groups.nextcloud.members = [ "nextcloud" config.services.nginx.user ];

      environment.systemPackages = [ occ ];

      services.mysql = lib.mkIf cfg.database.createLocally {
        enable = true;
        package = lib.mkDefault pkgs.mariadb;
        ensureDatabases = [ cfg.config.dbname ];
        ensureUsers = [{
          name = cfg.config.dbuser;
          ensurePermissions = { "${cfg.config.dbname}.*" = "ALL PRIVILEGES"; };
        }];
        # FIXME(@Ma27) Nextcloud isn't compatible with mariadb 10.6,
        # this is a workaround.
        # See https://help.nextcloud.com/t/update-to-next-cloud-21-0-2-has-get-an-error/117028/22
        settings = mkIf (versionOlder cfg.package.version "24") {
          mysqld = {
            innodb_read_only_compressed = 0;
          };
        };
        initialScript = pkgs.writeText "mysql-init" ''
          CREATE USER '${cfg.config.dbname}'@'localhost' IDENTIFIED BY '${builtins.readFile( cfg.config.dbpassFile )}';
          CREATE DATABASE IF NOT EXISTS ${cfg.config.dbname};
          GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER,
            CREATE TEMPORARY TABLES ON ${cfg.config.dbname}.* TO '${cfg.config.dbuser}'@'localhost'
            IDENTIFIED BY '${builtins.readFile( cfg.config.dbpassFile )}';
          FLUSH privileges;
        '';
      };

      services.nginx.enable = mkDefault true;

      services.nginx.virtualHosts.${cfg.hostName} = {
        root = cfg.package;
        locations = {
          "= /robots.txt" = {
            priority = 100;
            extraConfig = ''
              allow all;
              log_not_found off;
              access_log off;
            '';
          };
          "= /" = {
            priority = 100;
            extraConfig = ''
              if ( $http_user_agent ~ ^DavClnt ) {
                return 302 /remote.php/webdav/$is_args$args;
              }
            '';
          };
          "/" = {
            priority = 900;
            extraConfig = "rewrite ^ /index.php;";
          };
          "~ ^/store-apps" = {
            priority = 201;
            extraConfig = "root ${cfg.home};";
          };
          "~ ^/nix-apps" = {
            priority = 201;
            extraConfig = "root ${cfg.home};";
          };
          "^~ /.well-known" = {
            priority = 210;
            extraConfig = ''
              absolute_redirect off;
              location = /.well-known/carddav {
                return 301 /remote.php/dav;
              }
              location = /.well-known/caldav {
                return 301 /remote.php/dav;
              }
              location ~ ^/\.well-known/(?!acme-challenge|pki-validation) {
                return 301 /index.php$request_uri;
              }
              try_files $uri $uri/ =404;
            '';
          };
          "~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)".extraConfig = ''
            return 404;
          '';
          "~ ^/(?:\\.(?!well-known)|autotest|occ|issue|indie|db_|console)".extraConfig = ''
            return 404;
          '';
          "~ ^\\/(?:index|remote|public|cron|core\\/ajax\\/update|status|ocs\\/v[12]|updater\\/.+|oc[ms]-provider\\/.+|.+\\/richdocumentscode\\/proxy)\\.php(?:$|\\/)" = {
            priority = 500;
            extraConfig = ''
              include ${config.services.nginx.package}/conf/fastcgi.conf;
              fastcgi_split_path_info ^(.+?\.php)(\\/.*)$;
              set $path_info $fastcgi_path_info;
              try_files $fastcgi_script_name =404;
              fastcgi_param PATH_INFO $path_info;
              fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
              fastcgi_param HTTPS ${if cfg.https then "on" else "off"};
              fastcgi_param modHeadersAvailable true;
              fastcgi_param front_controller_active true;
              fastcgi_pass unix:${fpm.socket};
              fastcgi_intercept_errors on;
              fastcgi_request_buffering off;
              fastcgi_read_timeout 120s;
            '';
          };
          "~ \\.(?:css|js|woff2?|svg|gif|map)$".extraConfig = ''
            try_files $uri /index.php$request_uri;
            expires 6M;
            access_log off;
          '';
          "~ ^\\/(?:updater|ocs-provider|ocm-provider)(?:$|\\/)".extraConfig = ''
            try_files $uri/ =404;
            index index.php;
          '';
          "~ \\.(?:png|html|ttf|ico|jpg|jpeg|bcmap|mp4|webm)$".extraConfig = ''
            try_files $uri /index.php$request_uri;
            access_log off;
          '';
        };
        extraConfig = ''
          index index.php index.html /index.php$request_uri;
          ${optionalString (cfg.nginx.recommendedHttpHeaders) ''
            add_header X-Content-Type-Options nosniff;
            add_header X-XSS-Protection "1; mode=block";
            add_header X-Robots-Tag none;
            add_header X-Download-Options noopen;
            add_header X-Permitted-Cross-Domain-Policies none;
            add_header X-Frame-Options sameorigin;
            add_header Referrer-Policy no-referrer;
          ''}
          ${optionalString (cfg.https) ''
            add_header Strict-Transport-Security "max-age=${toString cfg.nginx.hstsMaxAge}; includeSubDomains" always;
          ''}
          client_max_body_size ${cfg.maxUploadSize};
          fastcgi_buffers 64 4K;
          fastcgi_hide_header X-Powered-By;
          gzip on;
          gzip_vary on;
          gzip_comp_level 4;
          gzip_min_length 256;
          gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
          gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

          ${optionalString cfg.webfinger ''
            rewrite ^/.well-known/host-meta /public.php?service=host-meta last;
            rewrite ^/.well-known/host-meta.json /public.php?service=host-meta-json last;
          ''}
        '';
      };
    }
  ]);

  meta.doc = ./nextcloud.xml;
}
