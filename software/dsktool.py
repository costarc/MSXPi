#from fs import open_fs
import sys
import fs

if len(sys.argv) < 2:
    print("Parameters:")
    print("/c   copy files")
    print("/l   list files")
    print("To copy a file to a disk image:\n")
    print("dskcp.py file diskimage.dsk:file")
    print("\n Directories are not supported")
    exit

try:
    if sys.argv[1].lower() == "dir":
            fatfile = fs.open_fs("fat://"+sys.argv[2])
            dirlist = fatfile.listdir("/")

            for file in dirlist:
                if "." in file:
                    name = file.split(".")[0].ljust(8,' ')
                    ext = file.split(".")[1].ljust(3,' ')
                else:
                    name = fn.ljust(8,' ')
                    ext = "   "
                
                fsize = str(fatfile.getsize(file)).rjust(8)
                moddate = str(fatfile.getmodified(file)).rjust(15)[:19]
                print(name,ext,fsize,moddate)
                
            walker = fs.walk.Walker(filter=['*'])
            for path, dirs, files in walker.walk(fatfile, namespaces=['details']):
                print("{} directories".format(len(dirs)))
                total = sum(info.size for info in files)
                print("{} bytes".format(total))

            quit()
            

    elif sys.argv[1].lower() == "copy":
        fname1 = sys.argv[2]
        dskfile = sys.argv[3].split(":")[0]
        fname2 = sys.argv[3].split(":")[1]
        print("Copying: {} to {}:{}".format(fname1,dskfile,fname2))
        
        inpfile = open(fname1,"rb")
        buf = inpfile.read()
        fatfile = fs.open_fs("fat://"+dskfile)
        fatfile.create(fname2, True)           # Overwrite is exists
        fatfile.writebytes(fname2,buf)                 # Write file contents
        print("\nDone")
except Exception as e:
    print(str(e))

        
        
