cd ..
rm -rf hardware/CPLD\ Project/db
rm -rf hardware/CPLD\ Project/output_files
rm -rf hardware/CPLD\ Project/incremental_db
rm hardware/CPLD\ Project/*.done
rm hardware/CPLD\ Project/*.jdi
rm hardware/CPLD\ Project/*.cdb
rm hardware/CPLD\ Project/*.hdb
rm hardware/CPLD\ Project/*.qmsg
rm hardware/CPLD\ Project/*.rdb
rm hardware/CPLD\ Project/*.ddb
rm hardware/CPLD\ Project/*.tdb
rm hardware/CPLD\ Project/*.hif
rm hardware/CPLD\ Project/*.summary
rm hardware/CPLD\ Project/*.qws
rm hardware/CPLD\ Project/*.rpt
rm hardware/CPLD\ Project/*.o
rm hardware/CPLD\ Project/*.cf
rm hardware/CPLD\ Project/*.pin
git add .
git status
cd -

