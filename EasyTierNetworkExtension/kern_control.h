#ifndef KERN_CONTROL_h
#define KERN_CONTROL_h


#define CTLIOCGINFO 0xc0644e03UL
struct ctl_info {
    unsigned int   ctl_id;
    char        ctl_name[96];
};
struct sockaddr_ctl {
    unsigned char      sc_len;
    unsigned char      sc_family;
    unsigned short   ss_sysaddr;
    unsigned int   sc_id;
    unsigned int   sc_unit;
    unsigned int   sc_reserved[5];
};

#endif
