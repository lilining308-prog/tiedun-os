/* 铁盾OS B3: KSU 白名单预置授权器 (tiedun-priv 模块内置)
 * 依据 KernelSU-Next 12759 内核 ABI: prctl(0xDEADBEEF, CMD_SET_APP_PROFILE, &app_profile, ..)
 * 仅 root 可调用(KSU 内核侧校验), 由 KSU 模块 service.sh 于开机执行。
 * SPDX-License-Identifier: GPL-3.0
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <unistd.h>

/* ===== 与 drivers/kernelsu/ksu.h 一致的结构(ABI 必须逐字节一致) ===== */
#define KERNEL_SU_OPTION 0xDEADBEEF
#define CMD_SET_APP_PROFILE 11
#define KSU_APP_PROFILE_VER 2
#define KSU_MAX_PACKAGE_NAME 256
#define KSU_MAX_GROUPS 32
#define KSU_SELINUX_DOMAIN 64

struct root_profile {
    int uid;
    int gid;
    int groups_count;
    int groups[KSU_MAX_GROUPS];
    struct {
        unsigned long long effective;
        unsigned long long permitted;
        unsigned long long inheritable;
    } capabilities;
    char selinux_domain[KSU_SELINUX_DOMAIN];
    int namespaces;
};

struct non_root_profile {
    _Bool umount_modules;
};

struct app_profile {
    unsigned int version;
    char key[KSU_MAX_PACKAGE_NAME];
    int current_uid;
    _Bool allow_su;
    union {
        struct {
            _Bool use_default;
            char template_name[KSU_MAX_PACKAGE_NAME];
            struct root_profile profile;
        } rp_config;
        struct {
            _Bool use_default;
            struct non_root_profile profile;
        } nrp_config;
    };
};

/* ABI 尺寸锁(arm64 LP64): 防止结构漂移与内核不一致 */
_Static_assert(sizeof(struct app_profile) == 776, "app_profile ABI size mismatch");
_Static_assert(sizeof(struct root_profile) == 240, "root_profile ABI size mismatch");

static int lookup_uid(const char *pkg)
{
    char line[512], name[256];
    int uid;
    FILE *f = fopen("/data/system/packages.list", "r");
    if (f) {
        while (fgets(line, sizeof(line), f)) {
            if (sscanf(line, "%255s %d", name, &uid) == 2 && !strcmp(name, pkg)) {
                fclose(f);
                return uid;
            }
        }
        fclose(f);
    }
    /* 兜底: 按应用数据目录属主取 uid */
    char path[320];
    struct stat st;
    snprintf(path, sizeof(path), "/data/user/0/%s", pkg);
    if (stat(path, &st) == 0)
        return (int)st.st_uid;
    return -1;
}

int main(int argc, char **argv)
{
    int rc = 0;
    if (argc < 2) {
        fprintf(stderr, "usage: %s <package> [package...]\n", argv[0]);
        return 2;
    }
    for (int i = 1; i < argc; i++) {
        const char *pkg = argv[i];
        int uid = lookup_uid(pkg);
        if (uid <= 0) {
            fprintf(stderr, "tiedun-ksu-grant: uid not found for %s\n", pkg);
            rc = 1;
            continue;
        }
        struct app_profile p;
        memset(&p, 0, sizeof(p));
        p.version = KSU_APP_PROFILE_VER;
        strncpy(p.key, pkg, KSU_MAX_PACKAGE_NAME - 1);
        p.current_uid = uid;
        p.allow_su = 1;
        p.rp_config.use_default = 1;
        unsigned int result = 0;
        long r = prctl(KERNEL_SU_OPTION, CMD_SET_APP_PROFILE,
                       (unsigned long)&p, 0UL, (unsigned long)&result);
        if (result == KERNEL_SU_OPTION) {
            printf("tiedun-ksu-grant: %s uid=%d -> allow_su (persisted)\n", pkg, uid);
        } else {
            fprintf(stderr, "tiedun-ksu-grant: %s uid=%d prctl ret=%ld result=0x%x (KSU未激活?)\n",
                    pkg, uid, r, result);
            rc = 1;
        }
    }
    return rc;
}
