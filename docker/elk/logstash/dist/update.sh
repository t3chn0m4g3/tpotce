#!/bin/bash

# Let's ensure normal operation on exit or if interrupted ...
function fuCLEANUP {
  exit 0
}
trap fuCLEANUP EXIT

# Check internet availability 
function fuCHECKINET () {
mySITES=$1
error=0
for i in $mySITES;
  do
    curl --connect-timeout 5 -Is $i 2>&1 > /dev/null
      if [ $? -ne 0 ];
        then
          let error+=1
      fi;
  done;
  echo $error
}

# Check for connectivity and download latest translation maps
myCHECK=$(fuCHECKINET "listbot.sicherheitstacho.eu")
if [ "$myCHECK" == "0" ];
  then
    echo "Connection to Listbot looks good, now downloading latest translation maps."
    cd /etc/listbot 
    aria2c -s16 -x 16 https://listbot.sicherheitstacho.eu/cve.yaml.bz2 && \
    aria2c -s16 -x 16 https://listbot.sicherheitstacho.eu/iprep.yaml.bz2 && \
    bunzip2 -f *.bz2
    cd /
  else
    echo "Cannot reach Listbot, starting Logstash without latest translation maps."
fi

# Distributed T-Pot installation needs a different pipeline config and autossh tunnel. 
if [ "$MY_TPOT_TYPE" == "POT" ];
  then
    echo
    echo "Distributed T-Pot setup, sending T-Pot logs to $MY_HIVE_IP."
    echo
    echo "T-Pot type: $MY_TPOT_TYPE"
    echo "Keyfile used: $MY_POT_PRIVATEKEYFILE"
    echo "Hive username: $MY_HIVE_USERNAME"
    echo "Hive IP: $MY_HIVE_IP"
    echo
    cp /usr/share/logstash/config/pipelines_pot.yml /usr/share/logstash/config/pipelines.yml
    autossh -f -M 0 -v -4 -l $MY_HIVE_USERNAME -i $MY_POT_PRIVATEKEYFILE -p 64295 -N -L64305:127.0.0.1:64305 $MY_HIVE_IP -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null"
    exit 0
fi

# We do want to enforce our es_template thus we always need to delete the default template, putting our default afterwards
# This is now done via common_configs.rb => overwrite default logstash template
echo "Removing logstash template."
curl -s -XDELETE http://elasticsearch:9200/_template/logstash
echo
echo "Checking if empty."
curl -s -XGET http://elasticsearch:9200/_template/logstash
echo
echo "Putting default template."
curl -s -XPUT "http://elasticsearch:9200/_template/logstash" -H 'Content-Type: application/json' -d'
{
  "index_patterns" : "logstash-*",
  "version" : 60001,
  "settings" : {
    "index.refresh_interval" : "5s",
    "number_of_shards" : 1,
    "index.number_of_replicas" : "0",
    "index.mapping.total_fields.limit" : "2000",
    "index.query": {
      "default_field": "*"
     }
  },
  "mappings" : {
    "dynamic_templates" : [ {
      "message_field" : {
        "path_match" : "message",
        "match_mapping_type" : "string",
        "mapping" : {
          "type" : "text",
          "norms" : false
        }
      }
    }, {
      "string_fields" : {
        "match" : "*",
        "match_mapping_type" : "string",
        "mapping" : {
          "type" : "text", "norms" : false,
          "fields" : {
            "keyword" : { "type": "keyword", "ignore_above": 256 }
          }
        }
      }
    } ],
    "properties" : {
      "@timestamp": { "type": "date"},
      "@version": { "type": "keyword"},
      "geoip"  : {
        "dynamic": true,
        "properties" : {
          "ip": { "type": "ip" },
          "location" : { "type" : "geo_point" },
          "latitude" : { "type" : "half_float" },
          "longitude" : { "type" : "half_float" }
        }
      }
    }
  }
}'
echo
