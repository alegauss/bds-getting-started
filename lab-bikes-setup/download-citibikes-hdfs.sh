#!/bin/bash
# Download trips data and setup hive

. env.sh

export FILE_HOST="https://s3.amazonaws.com/tripdata/"
export FILE_LIST="
JC-201901-citibike-tripdata.csv.zip
JC-201902-citibike-tripdata.csv.zip
JC-201903-citibike-tripdata.csv.zip
JC-201904-citibike-tripdata.csv.zip
JC-201905-citibike-tripdata.csv.zip
JC-201906-citibike-tripdata.csv.zip
JC-201907-citibike-tripdata.csv.zip
JC-201908-citibike-tripdata.csv.zip
JC-201909-citibike-tripdata.csv.zip
JC-201910-citibike-tripdata.csv.zip
JC-201911-citibike-tripdata.csv.zip
JC-201912-citibike-tripdata.csv.zip"

echo "Downloading bike rental data from New York City’s Citi Bike bicycle sharing service"
echo "You can view the Citi Bike licensing information here:  https://www.citibikenyc.com/data-sharing-policy"

echo "... retrieving station information from Citi Bikes feed"
curl https://gbfs.citibikenyc.com/gbfs/es/station_information.json | jq -c '.data.stations[]' > $TARGET_DIR/stations.json

echo "... copy the station JSON data to hdfs: /data/stations/"
hadoop fs -mkdir -p /data/stations
hadoop fs -put -f $TARGET_DIR/stations.json /data/stations/

echo "... retrieving detail trip data to $TARGET_DIR"

cd $TARGET_DIR
mkdir -p $TARGET_DIR/csv_tmp
rm $TARGET_DIR/csv_tmp/*

# download files from S3 and unzip

for file in $FILE_LIST 
do
   s3obj="https://s3.amazonaws.com/tripdata/$file"
   echo "... downloading $s3obj to $TARGET_DIR"
   curl --remote-name --silent $s3obj 
   echo "... extracting $file to $TARGET_DIR"
   unzip -o $TARGET_DIR/$file -d $TARGET_DIR/csv_tmp
done

# Remove first header line from each file
for file in $TARGET_DIR/csv_tmp/*.csv
do
  echo "... removing header row from $file"
  sed -i 1d $file
done

echo "... Upload csv files to /data/biketrips"
hadoop fs -mkdir -p /data/biketrips
hadoop fs -chmod 777 /data/biketrips
hadoop fs -rm /data/biketrips/*
hadoop fs -put -f $TARGET_DIR/csv_tmp/JC-*.csv /data/biketrips/

echo "... create Hive tables in database BIKES"

hive -e "
create database if not exists bikes;
DROP TABLE IF EXISTS bikes.trips_ext;
DROP TABLE IF EXISTS bikes.trips;

CREATE EXTERNAL TABLE bikes.trips_ext (
  trip_duration int,
  start_time string,
  stop_time  string,
  start_station_id int,
  start_station_name string,
  start_station_latitude decimal(13,10),
  start_station_longitude decimal(13,10),
  end_station_id int,
  end_station_name string,
  end_station_latitude decimal(13,10),
  end_station_longitude decimal(13,10),
  bike_id int,
  user_type string,
  birth_year int,
  gender int	   
 ) 
  ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
  STORED AS TEXTFILE
  location '/data/biketrips/'
;
  
create table bikes.trips ( 
  trip_duration int,
  start_month string,
  start_time string,
  start_hour int,
  stop_time  string,
  start_station_id int,
  start_station_name string,
  start_station_latitude decimal(13,10),
  start_station_longitude decimal(13,10),
  end_station_id int,
  end_station_name string,
  end_station_latitude decimal(13,10),
  end_station_longitude decimal(13,10),
  bike_id int,
  user_type string,
  birth_year int,
  gender int	
)
PARTITIONED BY (p_start_month string)
STORED AS PARQUET  
;

set hive.exec.dynamic.partition=true;
set hive.exec.dynamic.partition.mode=nonstrict;
FROM bikes.trips_ext t
INSERT OVERWRITE TABLE bikes.trips PARTITION(p_start_month) 
SELECT 
  trip_duration,
  substr(start_time, 1, 7),
  start_time,
  substr(start_time, 12, 2),
  stop_time,
  start_station_id,
  start_station_name,
  start_station_latitude,
  start_station_longitude,
  end_station_id,
  end_station_name,
  end_station_latitude,
  end_station_longitude,
  bike_id,
  user_type,
  birth_year,
  gender,
  substr(start_time, 1, 7)
;"