/*-
 * Copyright 2003 - 2005 Colin Percival
 * All rights reserved
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted providing that the following conditions 
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
 * IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#if 0
__FBSDID("$FreeBSD: src/usr.bin/bsdiff/bsdiff/bsdiff.c, v 1.1 2005/08/06 01:59:05 cperciva Exp $");
#endif

#include <sys/types.h>

#include <err.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MIN(x, y) (((x)<(y)) ? (x) : (y))

static void split(off_t *I, off_t *V, off_t start, off_t len, off_t h)
{
    off_t i, j, k, x, tmp, jj, kk;

    if (len < 16) {
        for (k = start; k < start + len; k += j) {
            j = 1; x = V[I[k] + h];
            for (i = 1; k + i < start + len; i++) {
                if (V[I[k + i] + h] < x) {
                    x = V[I[k + i] + h];
                    j = 0;
                };
                if (V[I[k + i] + h] == x) {
                    tmp = I[k + j]; I[k + j] = I[k + i]; I[k + i] = tmp;
                    j++;
                };
            };
            for (i = 0; i < j; i++)
                V[I[k + i]] = k + j - 1;
            if (j == 1)
                I[k] = -1;
        };
        return;
    };

    x = V[I[start + len/2] + h];
    jj = 0; kk = 0;
    for (i = start; i < start + len; i++) {
        if (V[I[i] + h] < x)
            jj++;
        if (V[I[i] + h] == x)
            kk++;
    };
    jj += start; kk += jj;

    i = start; j = 0; k = 0;
    while (i < jj) {
        if (V[I[i] + h] < x) {
            i++;
        } else if (V[I[i] + h] == x) {
            tmp = I[i]; I[i] = I[jj + j]; I[jj + j] = tmp;
            j++;
        } else {
            tmp = I[i]; I[i] = I[kk + k]; I[kk + k] = tmp;
            k++;
        };
    };

    while (jj + j < kk) {
        if (V[I[jj + j] + h] == x) {
            j++;
        } else {
            tmp = I[jj + j]; I[jj + j] = I[kk + k]; I[kk + k] = tmp;
            k++;
        };
    };

    if (jj > start)
        split(I, V, start, jj - start, h);

    for (i = 0; i < kk - jj; i++)
        V[I[jj + i]] = kk - 1;
    if (jj == kk - 1)
        I[jj] = -1;

    if (start + len > kk)
        split(I, V, kk, start + len - kk, h);
}

/* qsufsort(I, V, old, oldsize)
 *
 * Computes the suffix sort of the string at 'old' and stores the resulting
 * indices in 'I', using 'V' as a temporary array for the computation. */
static void qsufsort(off_t *I, off_t *V, u_char *old, off_t oldsize)
{
    off_t buckets[256];
    off_t i, h, len;

    /* count number of each byte  */
    for (i = 0; i < 256; i++)
        buckets[i] = 0;
    for (i = 0; i < oldsize; i++)
        buckets[old[i]]++;
    /* make buckets cumulative */
    for (i = 1; i < 256; i++)
        buckets[i] += buckets[i - 1];
    /* shift right by one */
    for (i = 255; i > 0; i--)
        buckets[i] = buckets[i - 1];
    buckets[0] = 0;
    /* at this point, buckets[c] is the number of bytes in the old file with
     * value less than c. */

    /* set up the sort order of the suffixes based solely on the first
     * character */
    for (i = 0; i < oldsize; i++)
        I[++buckets[old[i]]] = i;
    I[0] = oldsize;
    /* ? */
    for (i = 0; i < oldsize; i++)
        V[i] = buckets[old[i]];
    V[oldsize] = 0;
    /* forward any entries in the ordering which have the same initial
     * character */
    for (i = 1; i < 256; i++) {
        if (buckets[i] == buckets[i - 1] + 1)
            I[buckets[i]] = -1;
    }
    I[0] = -1;

    for (h = 1; I[0] != -(oldsize + 1); h += h) {
        len = 0;
        for (i = 0; i < oldsize + 1;) {
            if (I[i] < 0) {
                len -= I[i];
                i -= I[i];
            } else {
                if (len)
                    I[i - len] = -len;
                len = V[I[i]] + 1 - i;
                split(I, V, i, len, h);
                i += len;
                len = 0;
            }
        }
        if (len)
            I[i - len] = -len;
    };

    for (i = 0; i < oldsize + 1; i++) I[V[i]] = i;
}

/* matchlen(old, oldsize, new, newsize)
 *
 * Returns the length of the longest common prefix between 'old' and 'new'. */
static off_t matchlen(u_char *old, off_t oldsize, u_char *new, off_t newsize)
{
    off_t i;

    for (i = 0; (i < oldsize) && (i < newsize); i++)
    {
        if (old[i] != new[i])
            break;
    }

    return i;
}

/* search(I, old, oldsize, new, newsize, st, en, pos)
 *
 * Searches for the longest prefix of 'new' that occurs in 'old', stores its
 * offset in '*pos', and returns its length. 'I' should be the suffix sort of
 * 'old', and 'st' and 'en' are the lowest and highest indices in the suffix
 * sort to consider. If you're searching all suffixes, 'st = 0' and 'en =
 * oldsize - 1'. */
static off_t search(off_t *I, u_char *old, off_t oldsize,
        u_char *new, off_t newsize, off_t st, off_t en, off_t *pos)
{
    off_t x, y;

    if (en - st < 2) {
        x = matchlen(old + I[st], oldsize - I[st], new, newsize);
        y = matchlen(old + I[en], oldsize - I[en], new, newsize);

        if (x > y) {
            *pos = I[st];
            return x;
        } else {
            *pos = I[en];
            return y;
        }
    }

    x = st + (en - st)/2;
    if (memcmp(old + I[x], new, MIN(oldsize - I[x], newsize)) < 0) {
        return search(I, old, oldsize, new, newsize, x, en, pos);
    } else {
        return search(I, old, oldsize, new, newsize, st, x, pos);
    };
}

/* offtout(x, buf)
 * 
 * Writes the off_t 'x' portably to the array 'buf'. */
static void offtout(off_t x, u_char *buf)
{
    off_t y;

    if (x < 0)
        y = -x;
    else
        y = x;

    buf[0] = y % 256;
    y -= buf[0];
    y = y/256; buf[1] = y%256; y -= buf[1];
    y = y/256; buf[2] = y%256; y -= buf[2];
    y = y/256; buf[3] = y%256; y -= buf[3];
    y = y/256; buf[4] = y%256; y -= buf[4];
    y = y/256; buf[5] = y%256; y -= buf[5];
    y = y/256; buf[6] = y%256; y -= buf[6];
    y = y/256; buf[7] = y%256;

    if (x < 0)
        buf[7] |= 0x80;
}

int bsdiff(int argc, char *argv[]); // Added by AMM: suppresses a warning about the following not having a prototype.

int bsdiff(int argc, char *argv[])
{
    int fd;
    u_char *old,*new;           /* contents of old, new files */
    off_t oldsize, newsize;     /* length of old, new files */
    off_t *I,*V;                /* arrays used for suffix sort; I is ordering */
    off_t scan;                 /* position of current match in old file */
    off_t pos;                  /* position of current match in new file */
    off_t len;                  /* length of current match */
    off_t lastscan;             /* position of previous match in old file */
    off_t lastpos;              /* position of previous match in new file */
    off_t lastoffset;           /* lastpos - lastscan */
    off_t oldscore, scsc;       /* temp variables in match search */
    off_t s, Sf, lenf, Sb, lenb;    /* temp vars in match extension */
    off_t overlap, Ss, lens;
    off_t i;
    off_t dblen, eblen;         /* length of diff, extra sections */
    u_char *db,*eb;             /* contents of diff, extra sections */
    u_char buf[8];
    u_char header[32];
    FILE * pf;

    if (argc != 4)
        errx(1,"usage: %s oldfile newfile patchfile\n", argv[0]);

    /* Allocate oldsize + 1 bytes instead of oldsize bytes to ensure
        that we never try to malloc(0) and get a NULL pointer */
    if (((fd = open(argv[1], O_RDONLY, 0)) < 0) ||
        ((oldsize = lseek(fd, 0, SEEK_END)) == -1) ||
        ((old = malloc(oldsize + 1)) == NULL) ||
        (lseek(fd, 0, SEEK_SET) != 0) ||
        (read(fd, old, oldsize) != oldsize) ||
        (close(fd) == -1))
        err(1,"%s", argv[1]);

    if (((I = malloc((oldsize + 1) * sizeof(off_t))) == NULL) ||
        ((V = malloc((oldsize + 1) * sizeof(off_t))) == NULL))
        err(1, NULL);

    /* Do a suffix sort on the old file. */
    qsufsort(I, V, old, oldsize);

    free(V);

    /* Allocate newsize + 1 bytes instead of newsize bytes to ensure
        that we never try to malloc(0) and get a NULL pointer */
    if (((fd = open(argv[2], O_RDONLY, 0)) < 0) ||
        ((newsize = lseek(fd, 0, SEEK_END)) == -1) ||
        ((new = malloc(newsize + 1)) == NULL) ||
        (lseek(fd, 0, SEEK_SET) != 0) ||
        (read(fd, new, newsize) != newsize) ||
        (close(fd) == -1))
        err(1,"%s", argv[2]);

    if (((db = malloc(newsize + 1)) == NULL) ||
        ((eb = malloc(newsize + 1)) == NULL))
        err(1, NULL);
    dblen = 0;
    eblen = 0;

    /* Create the patch file */
    if ((pf = fopen(argv[3], "w")) == NULL)
        err(1, "%s", argv[3]);

    /* Header is
        0    8     "BSDIFN40"
        8    8    length of ctrl block
        16    8    length of diff block
        24    8    length of new file */
    /* File is
        0    32    Header
        32    ??    ctrl block
        ??    ??    diff block
        ??    ??    extra block */
    memcpy(header, "BSDIFN40", 8);
    offtout(0, header + 8);
    offtout(0, header + 16);
    offtout(newsize, header + 24);
    if (fwrite(header, 32, 1, pf) != 1)
        err(1, "fwrite(%s)", argv[3]);

    /* Compute the differences, writing ctrl as we go */
    scan = 0;
    len = 0;
    lastscan = 0;
    lastpos = 0;
    lastoffset = 0;
    while (scan < newsize) {
        oldscore = 0;

        for (scsc = scan += len; scan < newsize; scan++) {
            /* 'oldscore' is the number of characters that match between the
             * substrings 'old[lastoffset + scan:lastoffset + scsc]' and
             * 'new[scan:scsc]'. */
            len = search(I, old, oldsize, new + scan, newsize - scan,
                    0, oldsize, &pos);

            /* If this match extends further than the last one, add any new
             * matching characters to 'oldscore'. */
            for (; scsc < scan + len; scsc++) {
                if ((scsc + lastoffset < oldsize) &&
                    (old[scsc + lastoffset] == new[scsc]))
                    oldscore++;
            }

            /* Choose this as our match if it contains more than eight
             * characters that would be wrong if matched with a forward
             * extension of the previous match instead. */
            if (((len == oldscore) && (len != 0)) || 
                (len > oldscore + 8))
                break;

            /* Since we're advancing 'scan' by 1, remove the character under it
             * from 'oldscore' if it matches. */
            if ((scan + lastoffset < oldsize) &&
                (old[scan + lastoffset] == new[scan]))
                oldscore--;
        }

        /* Skip this section if we found an exact match that would be
         * better serviced by a forward extension of the previous match. */
        if ((len != oldscore) || (scan == newsize)) {
            /* Figure out how far forward the previous match should be
             * extended... */
            s = 0;
            Sf = 0;
            lenf = 0;
            for (i = 0; (lastscan + i < scan) && (lastpos + i < oldsize);) {
                if (old[lastpos + i] == new[lastscan + i])
                    s++;
                i++;
                if (s * 2 - i > Sf * 2 - lenf) {
                    Sf = s;
                    lenf = i;
                }
            }

            /* ... and how far backwards the next match should be extended. */
            lenb = 0;
            if (scan < newsize) {
                s = 0;
                Sb = 0;
                for (i = 1; (scan >= lastscan + i) && (pos >= i); i++) {
                    if (old[pos - i] == new[scan - i])
                        s++;
                    if (s * 2 - i > Sb * 2 - lenb) {
                        Sb = s;
                        lenb = i;
                    }
                }
            }

            /* If there is an overlap between the extensions, find the best
             * dividing point in the middle and reset 'lenf' and 'lenb'
             * accordingly. */
            if (lastscan + lenf > scan - lenb) {
                overlap = (lastscan + lenf) - (scan - lenb);
                s = 0;
                Ss = 0;
                lens = 0;
                for (i = 0; i < overlap; i++) {
                    if (new[lastscan + lenf - overlap + i] ==
                        old[lastpos + lenf - overlap + i])
                        s++;
                    if (new[scan - lenb + i] == old[pos - lenb + i])
                        s--;
                    if (s > Ss) {
                        Ss = s;
                        lens = i + 1;
                    }
                }

                lenf += lens - overlap;
                lenb -= lens;
            }

            /* Write the diff data for the last match to the diff section... */
            for (i = 0; i < lenf; i++)
                db[dblen + i] = new[lastscan + i] - old[lastpos + i];
            /* ... and, if there's a gap between the extensions just
             * calculated, write the data in that gap to the extra section. */
            for (i = 0; i< (scan - lenb) - (lastscan + lenf); i++)
                eb[eblen + i] = new[lastscan + lenf + i];

            /* Update the diff and extra section lengths accordingly. */
            dblen += lenf;
            eblen += (scan - lenb) - (lastscan + lenf);

            /* Write the following triple of integers to the control section:
             *  - length of the diff
             *  - length of the extra section
             *  - offset between the end of the diff and the start of the next
             *      diff, in the old file
             */
            offtout(lenf, buf);
            if (fwrite(buf, 8, 1, pf) != 1)
                errx(1, "fwrite");

            offtout((scan - lenb) - (lastscan + lenf), buf);
            if (fwrite(buf, 8, 1, pf) != 1)
                err(1, "fwrite");

            offtout((pos - lenb) - (lastpos + lenf), buf);
            if (fwrite(buf, 8, 1, pf) != 1)
                err(1, "fwrite");

            /* Update the variables describing the last match. Note that
             * 'lastscan' is set to the start of the current match _after_ the
             * backwards extension; the data in that extension will be written
             * in the next pass. */
            lastscan = scan - lenb;
            lastpos = pos - lenb;
            lastoffset = pos - scan;
        }
    }

    /* Compute size of compressed ctrl data */
    if ((len = ftello(pf)) == -1)
        err(1, "ftello");
    offtout(len - 32, header + 8);

    /* Write diff data */
    if (dblen && fwrite(db, dblen, 1, pf) != 1)
        err(1, "fwrite");

    /* Compute size of compressed diff data */
    if ((newsize = ftello(pf)) == -1)
        err(1, "ftello");
    offtout(newsize - len, header + 16);

    /* Write extra data */
    if (eblen && fwrite(eb, eblen, 1, pf) != 1)
        err(1, "fwrite");

    /* Seek to the beginning, write the header, and close the file */
    if (fseeko(pf, 0, SEEK_SET))
        err(1, "fseeko");
    if (fwrite(header, 32, 1, pf) != 1)
        err(1, "fwrite(%s)", argv[3]);
    if (fclose(pf))
        err(1, "fclose");

    /* Free the memory we used */
    free(db);
    free(eb);
    free(I);
    free(old);
    free(new);

    return 0;
}
