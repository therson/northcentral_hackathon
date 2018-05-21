#!/bin/bash

cp /root/northcentral_hackathon/druid/0_1_datasources.dat /var/lib/mysql-files/0_1_datasources.dat
cp /root/northcentral_hackathon/druid/0_2_metrics.dat /var/lib/mysql-files/0_2_metrics.dat
cp /root/northcentral_hackathon/druid/1_slices.dat /var/lib/mysql-files/1_slices.dat
cp /root/northcentral_hackathon/druid/2_slice_user.dat /var/lib/mysql-files/2_slice_user.dat
cp /root/northcentral_hackathon/druid/3_dashboards.dat /var/lib/mysql-files/3_dashboards.dat
cp /root/northcentral_hackathon/druid/4_dashboard_slices.dat /var/lib/mysql-files/4_dashboard_slices.dat
cp /root/northcentral_hackathon/druid/5_columns.dat /var/lib/mysql-files/5_columns.dat

mysql -u root --execute "LOAD DATA INFILE '/var/lib/mysql-files/0_1_datasources.dat' INTO TABLE superset.datasources"
mysql -u root --execute "LOAD DATA INFILE '/var/lib/mysql-files/0_2_metrics.dat' INTO TABLE superset.metrics"
mysql -u root --execute "LOAD DATA INFILE '/var/lib/mysql-files/1_slices.dat' INTO TABLE superset.slices"
mysql -u root --execute "LOAD DATA INFILE '/var/lib/mysql-files/2_slice_user.dat' INTO TABLE superset.slice_user"
mysql -u root --execute "LOAD DATA INFILE '/var/lib/mysql-files/3_dashboards.dat' INTO TABLE superset.dashboards"
mysql -u root --execute "LOAD DATA INFILE '/var/lib/mysql-files/4_dashboard_slices.dat' INTO TABLE superset.dashboard_slices"
mysql -u root --execute "LOAD DATA INFILE '/var/lib/mysql-files/5_columns.dat' INTO TABLE superset.columns"
