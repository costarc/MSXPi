AC_INIT([msxpi-server], m4_esyscmd([tr -d '\n' < VERSION]), [mariogar1979@gmail.com])
CFLAGS="-Wall -pthread -lpigpio -lrt -lcurl"
AC_SUBST(CFLAGS)

AM_INIT_AUTOMAKE
AM_MAINTAINER_MODE
AC_PROG_CC
AC_CONFIG_FILES([Makefile])

AC_CHECK_LIB([curl], [curl_easy_setopt], [echo "libcurl library is present"  > /dev/tty], [echo "libcurl library is not present" > /dev/tty] )

AC_CHECK_LIB([rt], [timer_create], [echo "librt library is present"  > /dev/tty], [echo "librt library is not present" > /dev/tty] )

AC_CHECK_LIB([pigpio], [gpioInitialise], [echo "pigpio library is present" > /dev/tty], [echo "pigpio library is not preset, please download from: http://abyz.co.uk/rpi/pigpio/download.html" > /dev/tty])

AC_OUTPUT
