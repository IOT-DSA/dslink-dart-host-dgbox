import "dart:async";
import "dart:convert";
import "dart:io";

import "package:dslink/dslink.dart" hide Link;
import "package:dslink/nodes.dart";

import "package:dslink_system/utils.dart";

LinkProvider link;

typedef Action(Map<String, dynamic> params);
typedef ActionWithPath(Path path, Map<String, dynamic> params);

addAction(handler) {
  return (String path) {
    var p = new Path(path);
    return new SimpleActionNode(path, (params) {
      if (handler is Action) {
        return handler(params);
      } else if (handler is ActionWithPath) {
        return handler(p, params);
      } else {
        throw new Exception("Bad Action Handler");
      }
    });
  };
}

verifyDependencies() async {
  if (!Platform.isLinux) {
    return;
  }

  List<String> tools = [
    "dnsmasq"
  ];

  if (!(await isProbablyDGBox())) {
    tools.add("hostapd");
  }

  for (var tool in tools) {
    if (await findExecutable(tool) == null) {
      await installPackage(tool);
    }
  }

  if (await isProbablyDGBox()) {
    var mf = new File("/usr/bin/python2");
    if (!(await mf.exists())) {
      var link = new Link("/usr/bin/python2");
      await link.create("/usr/bin/python");
    }
  }

  if (await findExecutable("hotspotd") == null) {
    var result = await exec("python2", args: [
      "setup.py",
      "install"
    ], workingDirectory: "tools/hotspotd", writeToBuffer: true);
    if (result.exitCode != 0) {
      print("Failed to install hotspotd:");
      stdout.write(result.output);
      exit(1);
    }
  }

  if (await fileExists("/etc/rpi-issue")) {
    var nf = new File("tools/hostapd_pi");
    await nf.copy("/usr/sbin/hostapd");
  }
}

String generateHotspotDaemonConfig(String wifi, String internet, String ssid, String ip, String netmask, String password) {
  return JSON.encode({
    "wlan": wifi,
    "inet": internet,
    "SSID": ssid,
    "ip": ip,
    "netmask": netmask,
    "password": password
  });
}

main(List<String> args) async {
  {
    var result = await Process.run("id", ["-u"]);

    if (result.stdout.trim() != "0") {
      print("This link must be run as the superuser.");
      exit(0);
    }

    await verifyDependencies();
  }

  var map = {
    "Shutdown": {
      r"$invokable": "write",
      r"$is": "shutdown"
    },
    "Reboot": {
      r"$invokable": "write",
      r"$is": "reboot"
    },
    "Execute_Command": {
      r"$invokable": "write",
      r"$is": "executeCommand",
      r"$name": "Execute Command",
      r"$params": [
        {
          "name": "command",
          "type": "string"
        }
      ],
      r"$result": "values",
      r"$columns": [
        {
          "name": "output",
          "type": "string",
          "editor": "textarea"
        },
        {
          "name": "exitCode",
          "type": "int"
        }
      ]
    },
    "Hostname": {
      r"$type": "string",
      "?value": Platform.localHostname
    },
    "Get_Current_Time": {
      r"$name": "Get Current Time",
      r"$is": "getCurrentTime",
      r"$invokable": "read",
      r"$columns": [
        {
          "name": "time",
          "type": "string"
        }
      ]
    },
    "Set_Current_Time": {
      r"$name": "Set Current Time",
      r"$invokable": "write",
      r"$is": "setDateTime",
      r"$params": [
        {
          "name": "time",
          "type": "string"
        }
      ],
      r"$columns": [
        {
          "name": "success",
          "type": "bool"
        },
        {
          "name": "message",
          "type": "string"
        }
      ],
      r"$result": "values"
    },
    "Timezone": {
      r"$type": "string",
      r"?value": await getCurrentTimezone(),
      "Set": {
        r"$invokable": "write",
        r"$is": "setCurrentTimezone",
        r"$params": [
          {
            "name": "timezone",
            "type": buildEnumType(await getAllTimezones())
          }
        ]
      }
    },
    "List_Directory": {
      r"$invokable": "read",
      r"$name": "List Directory",
      r"$is": "listDirectory",
      r"$result": "table",
      r"$params": [
        {
          "name": "directory",
          "type": "string"
        }
      ],
      r"$columns": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "path",
          "type": "string"
        },
        {
          "name": "type",
          "type": "string"
        }
      ]
    },
    "Network": {
      r"$name": "Network",
      "Start_Access_Point": {
        r"$name": "Start Access Point",
        r"$is": "startAccessPoint",
        r"$invokable": "write",
        r"$result": "values"
      },
      "Stop_Access_Point": {
        r"$name": "Stop Access Point",
        r"$is": "stopAccessPoint",
        r"$invokable": "write",
        r"$result": "values"
      },
      "Restart_Access_Point": {
        r"$name": "Restart Access Point",
        r"$is": "restartAccessPoint",
        r"$invokable": "write",
        r"$result": "values"
      },
      "Get_Access_Point_Status": {
        r"$name": "Get Access Point Status",
        r"$is": "getAccessPointStatus",
        r"$invokable": "write",
        r"$result": "values",
        r"$columns": [
          {
            "name": "up",
            "type": "bool"
          }
        ]
      },
      "Get_Access_Point_Settings": {
        r"$name": "Get Access Point Settings",
        r"$is": "getAccessPointConfiguration",
        r"$invokable": "write",
        r"$columns": [
          {
            "name": "key",
            "type": "string"
          },
          {
            "name": "value",
            "type": "string"
          }
        ],
        r"$result": "table"
      },
      "Configure_Access_Point": {
        r"$name": "Configure Access Point",
        r"$is": "configureAccessPoint",
        r"$invokable": "write",
        r"$params": [
          {
            "name": "ssid",
            "type": "string",
            "default": "DSA"
          },
          {
            "name": "password",
            "type": "string"
          },
          {
            "name": "ip",
            "type": "string",
            "default": "192.168.42.1"
          }
        ],
        r"$result": "values",
        r"$columns": [
          {
            "name": "success",
            "type": "bool"
          },
          {
            "name": "message",
            "type": "string"
          }
        ]
      },
      "Name_Servers": {
        r"$name": "Nameservers",
        r"$type": "string",
        "?value": (await getCurrentNameServers()).join(",")
      }
    }
  };

  if (!(await isProbablyDGBox())) {
    List mfj = map["Network"]["Configure_Access_Point"][r"$params"];
    mfj.insertAll(0, [
      {
        "name": "wifi",
        "type": "enum[]"
      },
      {
        "name": "internet",
        "type": "enum[]"
      }
    ]);
  }

  link = new LinkProvider(args, "Host-",
    defaultNodes: map, profiles: {
    "reboot": addAction((Map<String, dynamic> params) {
      System.reboot();
    }),
    "startAccessPoint": addAction((Map<String, dynamic> params) async {
      await startAccessPoint();
    }),
    "stopAccessPoint": addAction((Map<String, dynamic> params) async {
      await stopAccessPoint();
    }),
    "restartAccessPoint": addAction((Map<String, dynamic> params) async {
      await stopAccessPoint();
      await startAccessPoint();
    }),
    "getAccessPointStatus": addAction((Map<String, dynamic> params) async {
      return {
        "up": await isAccessPointOn()
      };
    }),
    "shutdown": addAction((Map<String, dynamic> params) {
      System.shutdown();
    }),
    "configureNetworkManual": addAction((Path path, Map<String, dynamic> params) async {
      var name = new Path(path.parentPath).name;
      var result = await configureNetworkManual(name, params["ip"], params["netmask"], params["router"]);

      return {
        "success": result
      };
    }),
    "configureNetworkAutomatic": addAction((Path path, Map<String, dynamic> params) async {
      var name = new Path(path.parentPath).name;
      var result = await configureNetworkAutomatic(name);

      return {
        "success": result
      };
    }),
    "scanWifiNetworks": addAction((Path path, Map<String, dynamic> params) async {
      var name = new Path(path.parentPath).name;
      var result = await scanWifiNetworks(name);

      return result.map((WifiNetwork x) => x.toRows());
    }),
    "getNetworkAddresses": addAction((Path path, Map<String, dynamic> params) async {
      var name = new Path(path.parentPath).name;
      var interfaces = await NetworkInterface.list();
      var interface = interfaces.firstWhere((x) => x.name == name, orElse: () => null);

      if (interface == null) {
        return [];
      }

      return interface.addresses.map((x) => {
        "address": x.address
      });
    }),
    "setWifiNetwork": addAction((Path path, Map<String, dynamic> params) async {
      var name = new Path(path.parentPath).name;
      var ssid = params["ssid"];
      var password = params["password"];

      return {
        "success": await setWifiNetwork(name, ssid, password)
      };
    }),
    "setCurrentTimezone": addAction((Map<String, dynamic> params) async {
      await setCurrentTimezone(params["timezone"]);
      await updateTimezone();
    }),
    "configureAccessPoint": addAction((Path path, Map<String, dynamic> params) async {
      String ssid = params["ssid"];
      String password = params["password"];
      String ip = params["ip"];

      if (await isProbablyDGBox()) {
        var uapConfig = [
          "ADDRESS=${ip}",
          "SSID=\"${ssid}\"",
          "PASSKEY=\"${password}\""
        ];

        var uapFile = new File("/root/.uap0.conf");
        await uapFile.writeAsString(uapConfig.join("\n"));
        var ml = ip.split(".").take(3).join(".");
        var dhcpConfig = [
          "start\t${ml}.100",
          "end\t${ml}.200",
          "interface\tuap0",
          "opt\tlease\t86400",
          "opt\trouter\t${ml}.1",
          "opt\tsubnet\t255.255.255.0",
          "opt\tdns\t${ml}.1",
          "opt\tdomain\tlocaldomain",
          "max_leases\t101",
          "lease_file\t/var/lib/udhcpd.leases",
          "auto_time\t5"
        ];
        var dhcpFile = new File("/etc/udhcpd.conf");
        await dhcpFile.writeAsString(dhcpConfig.join("\n"));
        return {
          "success": true,
          "message": "Success!"
        };
      }

      var wifi = params["wifi"];
      var internet = params["internet"];
      if (wifi == internet) {
        return {
          "success": false,
          "message": "Access Point Interface cannot be the same as the Internet Interface"
        };
      }

      var config = generateHotspotDaemonConfig(wifi, internet, ssid, ip, "255.255.255.0", password);

      var file = new File("${await getPythonModuleDirectory()}/hotspotd.json");
      if (!(await file.exists())) {
        await file.create(recursive: true);
      }

      await file.writeAsString(config);

      return {
        "success": true,
        "message": "Success!"
      };
    }),
    "executeCommand": addAction((Map<String, dynamic> params) async {
      var cmd = params["command"];
      var result = await exec("bash", args: ["-c", cmd], writeToBuffer: true);

      return {
        "output": result.output,
        "exitCode": result.exitCode
      };
    }),
    "listDirectory": addAction((Map<String, dynamic> params) async {
      var dir = new Directory(params["directory"]);

      try {
        return dir.list().asyncMap((x) async {
          return {
            "name": x.path.split("/").last,
            "path": x.path,
            "type": fseType(x)
          };
        }).toList();
      } catch (e) {
        return [];
      }
    }),
    "getCurrentTime": addAction((Map<String, dynamic> params) {
      return {
        "time": new DateTime.now().toIso8601String()
      };
    }),
    "setDateTime": addAction((Map<String, dynamic> params) async {
      try {
        var time = DateTime.parse(params["time"]);
        var result = await Process.run("date", [createSystemTime(time)]);
        return {
          "success": result.exitCode == 0,
          "message": ""
        };
      } catch (e) {
        return {
          "success": false,
          "message": e.toString()
        };
      }
    }),
    "getAccessPointConfiguration": addAction((Path path, Map<String, dynamic> params) async {
      if (await isProbablyDGBox()) {
        var file = new File("/root/.uap0.conf");
        var content = await file.readAsString();
        var lines = content.split("\n");
        var map = {};
        for (var line in lines) {
          line = line.trim();

          if (line.isEmpty) {
            continue;
          }

          var parts = line.split("=");
          var key = parts[0];
          var value = parts.skip(1).join("=");
          if (value.startsWith('"') && value.endsWith('"')) {
            value = value.substring(1, value.length - 1);
          }

          map[key] = value;
        }
        return [
          {
            "key": "ip",
            "value": map["ADDRESS"]
          },
          {
            "key": "ssid",
            "value": map["SSID"]
          },
          {
            "key": "password",
            "value": map["PASSKEY"]
          },
          {
            "key": "netmask",
            "value": "255.255.255.0"
          }
        ];
      }

      var m = [];
      var file = new File("${await getPythonModuleDirectory()}/hotspotd.json");
      if (!(await file.exists())) {
        return [];
      }

      var json = JSON.decode(await file.readAsString());
      for (var key in json.keys) {
        m.add({
          "key": key.toLowerCase(),
          "value": json[key]
        });
      }

      return m;
    }),
    "enableCaptivePortal": addAction((Map<String, dynamic> params) async {
      var conf = await readCaptivePortalConfig();
      conf = removeCaptivePortalConfig(conf);
      SimpleActionNode gaps = link["/Network/Get_Access_Point_Settings"];
      var cpn = await gaps.onInvoke({});
      if (cpn != null && cpn.containsKey("ip")) {
        conf += "\n" + getDnsMasqCaptivePortal(cpn["ip"]);
      }
      await writeCaptivePortalConfig(conf);
      await restartDnsMasq();

      return {
        "success": true
      };
    }),
    "disableCaptivePortal": addAction((Map<String, dynamic> params) async {
      var conf = await readCaptivePortalConfig();
      conf = removeCaptivePortalConfig(conf);
      await writeCaptivePortalConfig(conf);
      await restartDnsMasq();

      return {
        "success": true
      };
    })
  }, autoInitialize: false);

  link.init();
  link.connect();

  timer = new Timer.periodic(new Duration(seconds: 15), (_) async {
    await syncNetworkStuff();
  });

  await syncNetworkStuff();
}

Timer timer;

Future<List<String>> listNetworkInterfaces() async {
  var result = await Process.run("ifconfig", []);
  List<String> lines = result.stdout.split("\n");
  var ifaces = [];
  for (var line in lines) {
    if (line.isNotEmpty && line[0] != " " && line[0] != "\t") {
      var iface = line.split(" ")[0];
      if (iface.endsWith(":")) {
        iface = iface.substring(0, iface.length - 1);
      }
      ifaces.add(iface);
    }
  }
  return ifaces;
}

syncNetworkStuff() async {
  var nameservers = (await getCurrentNameServers()).join(",");

  if (nameservers.isNotEmpty) {
    link.updateValue("/Network/Name_Servers", nameservers);
  }

  List<String> ifaces = await listNetworkInterfaces();
  SimpleNode inode = link["/Network"];

  for (SimpleNode child in inode.children.values) {
    if (child.configs[r"$host_network"] != null && !ifaces.contains(child.configs[r"$host_network"])) {
      inode.removeChild(child);
    }
  }

  var wifis = [];
  var names = [];

  for (String iface in ifaces) {
    if (iface == "lo" || inode.children.containsKey(iface)) {
      continue;
    }

    var m = {};

    names.add(iface);

    m[r"$host_network"] = iface;

    m["Get_Addresses"] = {
      r"$name": "Get Addresses",
      r"$invokable": "write",
      r"$is": "getNetworkAddresses",
      r"$result": "table",
      r"$columns": [
        {
          "name": "address",
          "type": "string"
        }
      ]
    };

    m["Configure_Automatically"] = {
      r"$name": "Configure Automatically",
      r"$invokable": "write",
      r"$is": "configureNetworkAutomatic",
      r"$result": "values",
      r"$columns": [
        {
          "name": "success",
          "type": "bool"
        }
      ]
    };

    m["Configure_Manually"] = {
      r"$name": "Configure Manually",
      r"$invokable": "write",
      r"$is": "configureNetworkManual",
      r"$params": [
        {
          "name": "ip",
          "type": "string"
        },
        {
          "name": "netmask",
          "type": "string"
        },
        {
          "name": "gateway",
          "type": "string"
        }
      ],
      r"$columns": [
        {
          "name": "success",
          "type": "bool"
        }
      ],
      r"$result": "values"
    };

    if (await isWifiInterface(iface)) {
      wifis.add(iface);
      m["Scan_Wifi_Networks"] = {
        r"$name": "Scan WiFi Networks",
        r"$invokable": "write",
        r"$is": "scanWifiNetworks",
        r"$result": "table",
        r"$columns": [
          {
            "name": "ssid",
            "type": "string"
          },
          {
            "name": "hasSecurity",
            "type": "bool"
          }
        ]
      };

      m["Set_Wifi_Network"] = {
        r"$name": "Set WiFi Network",
        r"$invokable": "write",
        r"$is": "setWifiNetwork",
        r"$result": "values",
        r"$params": [
          {
            "name": "ssid",
            "type": "string"
          },
          {
            "name": "password",
            "type": "string"
          }
        ],
        r"$columns": [
          {
            "name": "success",
            "type": "bool"
          }
        ]
      };
    }

    link.addNode("/Network/${iface}", m);
  }

  if (!(await isProbablyDGBox())) {
    (link["/Network/Configure_Access_Point"].configs[r"$params"] as List)[0]["type"] = buildEnumType(wifis);
    (link["/Network/Configure_Access_Point"].configs[r"$params"] as List)[1]["type"] = buildEnumType(names);
  }
}

Future<String> getPythonModuleDirectory() async {
  var result = await exec("python2", args: ["-"], stdin: [
  "import hotspotd.main",
  "x = hotspotd.main.__file__.split('/')",
  "print('/'.join(x[0:len(x) - 1]))"
  ].join("\n"), writeToBuffer: true);

  return result.stdout.trim();
}

Future updateTimezone() async {
  link.updateValue("/Timezone", await getCurrentTimezone());
}
