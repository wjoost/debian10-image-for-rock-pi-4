/*
 * Resize a disk with a GPT partition
 *
 * CRC Routines: COPYRIGHT (C) 1986 Gary S. Brown.  You may use this program, or
 *               code or tables extracted from it, as desired without restriction.
 */

#define _LARGEFILE64_SOURCE

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <inttypes.h>
#include <endian.h>
#include <stdlib.h>
#include <stddef.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <linux/fs.h>

#define STANDARD_BLOCKSIZE	512
#define NUM_MBR_PART_RECORDS	4
#define MBR_SIGNATURE		0xAA55
#define MBR_OSTYPE_PROTECTIVE	0xEE

#define MAX_CYLINDERS		1023
#define MAX_HEADS		255
#define MAX_SECTORS		63

#define MAX_PARTITION_ENTRYS	128

/* A MBR partition record */
typedef struct s_mbr_partition_record {
	uint8_t		boot_indicator;
	uint8_t		starting_chs[3];
	uint8_t		ostype;
	uint8_t		ending_chs[3];
	uint32_t	starting_lba;
	uint32_t	size_in_lba;
} __attribute__ ((packed)) t_mbr_partition_record;

/* A MBR */
typedef struct s_mbr_sector {
	uint8_t		boot_code[440];
	uint32_t	unique_mbr_disk_signature;
	uint16_t	unknown;
	t_mbr_partition_record partition_record[NUM_MBR_PART_RECORDS];
	uint16_t	signature;
	uint8_t		reserved[];
} __attribute__ ((packed)) t_mbr_sector;

/* GPT header */
typedef struct s_gpt_header {
	uint8_t		signature[8];
	uint8_t		revision[4];
	uint32_t	header_size;
	uint32_t	header_crc32;
	uint32_t	reserved1;
	uint64_t	my_lba;
	uint64_t	alternate_lba;
	uint64_t	first_usable_lba;
	uint64_t	last_usable_lba;
	uint8_t		disk_guid[16];
	uint64_t	partition_entry_lba;
	uint32_t	number_of_partition_entries;
	uint32_t	size_of_partition_entry;
	uint32_t	partition_entry_array_crc32;
	uint8_t		reserved2[];
} __attribute__ ((packed)) t_gpt_header;

/* GPT signature */
static const uint8_t gpt_signature[8] = {
	0x45, 0x46, 0x49, 0x20, 0x50, 0x41, 0x52, 0x54
};

/* GPT revision */
static const uint8_t gpt_revision[4] = {
	0x00, 0x00, 0x01, 0x00
};

/* GPT partition record */
typedef struct s_gpt_record {
	uint8_t		partition_type_guid[16];
	uint8_t		unique_partition_guid[16];
	uint64_t	starting_lba;
	uint64_t	ending_lba;
	uint64_t	attributes;
	uint8_t		partition_name[72];
} __attribute__ ((packed)) t_gpt_record;

/* Update crc32 checksum */
static uint32_t crc32_add_char(uint32_t crc, uint8_t c) {
	static const uint32_t crc32_tab[] = {
		0x00000000L, 0x77073096L, 0xee0e612cL, 0x990951baL, 0x076dc419L,
		0x706af48fL, 0xe963a535L, 0x9e6495a3L, 0x0edb8832L, 0x79dcb8a4L,
		0xe0d5e91eL, 0x97d2d988L, 0x09b64c2bL, 0x7eb17cbdL, 0xe7b82d07L,
		0x90bf1d91L, 0x1db71064L, 0x6ab020f2L, 0xf3b97148L, 0x84be41deL,
		0x1adad47dL, 0x6ddde4ebL, 0xf4d4b551L, 0x83d385c7L, 0x136c9856L,
		0x646ba8c0L, 0xfd62f97aL, 0x8a65c9ecL, 0x14015c4fL, 0x63066cd9L,
		0xfa0f3d63L, 0x8d080df5L, 0x3b6e20c8L, 0x4c69105eL, 0xd56041e4L,
		0xa2677172L, 0x3c03e4d1L, 0x4b04d447L, 0xd20d85fdL, 0xa50ab56bL,
		0x35b5a8faL, 0x42b2986cL, 0xdbbbc9d6L, 0xacbcf940L, 0x32d86ce3L,
		0x45df5c75L, 0xdcd60dcfL, 0xabd13d59L, 0x26d930acL, 0x51de003aL,
		0xc8d75180L, 0xbfd06116L, 0x21b4f4b5L, 0x56b3c423L, 0xcfba9599L,
		0xb8bda50fL, 0x2802b89eL, 0x5f058808L, 0xc60cd9b2L, 0xb10be924L,
		0x2f6f7c87L, 0x58684c11L, 0xc1611dabL, 0xb6662d3dL, 0x76dc4190L,
		0x01db7106L, 0x98d220bcL, 0xefd5102aL, 0x71b18589L, 0x06b6b51fL,
		0x9fbfe4a5L, 0xe8b8d433L, 0x7807c9a2L, 0x0f00f934L, 0x9609a88eL,
		0xe10e9818L, 0x7f6a0dbbL, 0x086d3d2dL, 0x91646c97L, 0xe6635c01L,
		0x6b6b51f4L, 0x1c6c6162L, 0x856530d8L, 0xf262004eL, 0x6c0695edL,
		0x1b01a57bL, 0x8208f4c1L, 0xf50fc457L, 0x65b0d9c6L, 0x12b7e950L,
		0x8bbeb8eaL, 0xfcb9887cL, 0x62dd1ddfL, 0x15da2d49L, 0x8cd37cf3L,
		0xfbd44c65L, 0x4db26158L, 0x3ab551ceL, 0xa3bc0074L, 0xd4bb30e2L,
		0x4adfa541L, 0x3dd895d7L, 0xa4d1c46dL, 0xd3d6f4fbL, 0x4369e96aL,
		0x346ed9fcL, 0xad678846L, 0xda60b8d0L, 0x44042d73L, 0x33031de5L,
		0xaa0a4c5fL, 0xdd0d7cc9L, 0x5005713cL, 0x270241aaL, 0xbe0b1010L,
		0xc90c2086L, 0x5768b525L, 0x206f85b3L, 0xb966d409L, 0xce61e49fL,
		0x5edef90eL, 0x29d9c998L, 0xb0d09822L, 0xc7d7a8b4L, 0x59b33d17L,
		0x2eb40d81L, 0xb7bd5c3bL, 0xc0ba6cadL, 0xedb88320L, 0x9abfb3b6L,
		0x03b6e20cL, 0x74b1d29aL, 0xead54739L, 0x9dd277afL, 0x04db2615L,
		0x73dc1683L, 0xe3630b12L, 0x94643b84L, 0x0d6d6a3eL, 0x7a6a5aa8L,
		0xe40ecf0bL, 0x9309ff9dL, 0x0a00ae27L, 0x7d079eb1L, 0xf00f9344L,
		0x8708a3d2L, 0x1e01f268L, 0x6906c2feL, 0xf762575dL, 0x806567cbL,
		0x196c3671L, 0x6e6b06e7L, 0xfed41b76L, 0x89d32be0L, 0x10da7a5aL,
		0x67dd4accL, 0xf9b9df6fL, 0x8ebeeff9L, 0x17b7be43L, 0x60b08ed5L,
		0xd6d6a3e8L, 0xa1d1937eL, 0x38d8c2c4L, 0x4fdff252L, 0xd1bb67f1L,
		0xa6bc5767L, 0x3fb506ddL, 0x48b2364bL, 0xd80d2bdaL, 0xaf0a1b4cL,
		0x36034af6L, 0x41047a60L, 0xdf60efc3L, 0xa867df55L, 0x316e8eefL,
		0x4669be79L, 0xcb61b38cL, 0xbc66831aL, 0x256fd2a0L, 0x5268e236L,
		0xcc0c7795L, 0xbb0b4703L, 0x220216b9L, 0x5505262fL, 0xc5ba3bbeL,
		0xb2bd0b28L, 0x2bb45a92L, 0x5cb36a04L, 0xc2d7ffa7L, 0xb5d0cf31L,
		0x2cd99e8bL, 0x5bdeae1dL, 0x9b64c2b0L, 0xec63f226L, 0x756aa39cL,
		0x026d930aL, 0x9c0906a9L, 0xeb0e363fL, 0x72076785L, 0x05005713L,
		0x95bf4a82L, 0xe2b87a14L, 0x7bb12baeL, 0x0cb61b38L, 0x92d28e9bL,
		0xe5d5be0dL, 0x7cdcefb7L, 0x0bdbdf21L, 0x86d3d2d4L, 0xf1d4e242L,
		0x68ddb3f8L, 0x1fda836eL, 0x81be16cdL, 0xf6b9265bL, 0x6fb077e1L,
		0x18b74777L, 0x88085ae6L, 0xff0f6a70L, 0x66063bcaL, 0x11010b5cL,
		0x8f659effL, 0xf862ae69L, 0x616bffd3L, 0x166ccf45L, 0xa00ae278L,
		0xd70dd2eeL, 0x4e048354L, 0x3903b3c2L, 0xa7672661L, 0xd06016f7L,
		0x4969474dL, 0x3e6e77dbL, 0xaed16a4aL, 0xd9d65adcL, 0x40df0b66L,
		0x37d83bf0L, 0xa9bcae53L, 0xdebb9ec5L, 0x47b2cf7fL, 0x30b5ffe9L,
		0xbdbdf21cL, 0xcabac28aL, 0x53b39330L, 0x24b4a3a6L, 0xbad03605L,
		0xcdd70693L, 0x54de5729L, 0x23d967bfL, 0xb3667a2eL, 0xc4614ab8L,
		0x5d681b02L, 0x2a6f2b94L, 0xb40bbe37L, 0xc30c8ea1L, 0x5a05df1bL,
		0x2d02ef8dL
	};

	return crc32_tab[(crc ^ c) & 0xff] ^ (crc >> 8);
}

/* Calculate crc32 checksum */
static uint32_t ul_crc32(uint32_t seed, const uint8_t *buf, size_t len) {
	uint32_t crc = seed;
	const uint8_t *p = buf;

	while (len--) {
		crc = crc32_add_char(crc, *(p++));
	}

	return crc;
}

/* Calcute crc32 checksum with a gap filled with 0s */
static uint32_t ul_crc32_exclude_offset(uint32_t seed, const uint8_t *buf, size_t len,
                                        size_t exclude_off, size_t exclude_len) {
	uint32_t crc = seed;
	const uint8_t *p = buf;
	size_t i;

	for (i = 0; i < len; i++) {
		if ( (i >= exclude_off) && (i < exclude_off + exclude_len) ) {
			crc = crc32_add_char(crc, 0);
		} else {
			crc = crc32_add_char(crc, *p);
		}
		p++;
	}

	return crc;
}

/* Main program */
int main(int argc, char *argv[]) {
	int fd;
	uint64_t device_size;
	struct stat statbuf;
	int block_size;
	t_mbr_sector *mbr;
	int rc;
	int i;
	int protective_part;
	unsigned device_size_chs;
	unsigned cylinder;
	unsigned head;
	unsigned sector;
	union {
		t_gpt_header header;
		uint8_t data[sizeof(t_gpt_header)];
	} *primary_gpt_header, *alternate_gpt_header;
	union {
		t_gpt_record record;
		uint8_t data[sizeof(t_gpt_record)];
	} *partition_table;
	unsigned long partition_table_size;
	uint32_t crc;
	uint64_t new_backup_part_lba;
	uint64_t new_backup_gpt_lba;
	uint64_t old_backup_part_lba;
	uint64_t old_backup_gpt_lba;
	uint8_t *zeroes;

	/* Check arguments */
	if (argc != 2) {
		fprintf(stderr,"Usage: %s <blockdevice|imagefile>\n", argv[0]);
		return 1;
	}

	/* Get size and blocksize of blockdevice or imagefile */
	fd = open(argv[1], O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		fprintf(stderr,"Cannot open %s: %s (%d).\n", argv[1], strerror(errno), errno);
		return 1;
	}

	if (ioctl(fd, BLKGETSIZE64, &device_size) < 0) {
		if (fstat(fd, &statbuf) < 0) {
			fprintf(stderr,"Cannot determine size of %s.\n", argv[1]);
			close(fd);
			return 1;
		}
		device_size = statbuf.st_size;
		block_size = STANDARD_BLOCKSIZE;
	} else if (ioctl(fd, BLKSSZGET, &block_size) < 0) {
		fprintf(stderr,"Cannot determine block size of %s.\n", argv[1]);
		close(fd);
		return 1;
	}

	/* Show size */
	printf("Disk size: %" PRIu64 " GiB\n", (device_size / (1024 * 1024 * 1024)));
	printf("Block size: %d Bytes\n", block_size);

	/* Load MBR */
	mbr = malloc(block_size);
	if (mbr == NULL) {
		fputs("Cannot allocate storage.\n", stderr);
		close(fd);
		return 1;
	}
	if ( ( rc = read(fd, mbr, block_size) ) != block_size ) {
		if (rc < 0) {
			fprintf(stderr,"Cannot read MBR of %s: %s (%d).\n", argv[1], strerror(errno), errno);
		} else {
			fprintf(stderr,"Cannot read MBR of %s: Short read.\n", argv[1]);
		}
		close(fd);
		free(mbr);
		return 1;
	}

	/* Check signature of MBR */
	if (le16toh(mbr->signature) != MBR_SIGNATURE) {
		fputs("MBR has a wrong signature.\n", stderr);
		free(mbr);
		close(fd);
		return 1;
	}

	/* Search protective MBR partition */
	protective_part = -1;
	for (i = 0; i < NUM_MBR_PART_RECORDS; i++) {
		if (mbr->partition_record[i].ostype == MBR_OSTYPE_PROTECTIVE) {
			if (protective_part != -1) {
				fputs("More than one protective MBR partition found.\n", stderr);
				free(mbr);
				close(fd);
				return 1;
			}
			protective_part = i;
		}
	}
	if (protective_part < 0) {
		fputs("Cannot find protective MBR partition.\n", stderr);
		free(mbr);
		close(fd);
		return 1;
	}

	/* Check protective MBR partition entry */
	if ( le32toh(mbr->partition_record[protective_part].starting_lba) != 1) {
		fputs("Bad protective MBR partition.\n", stderr);
		free(mbr);
		close(fd);
		return 1;
	}

	/* Create new values for protective MBR partition entry */
	mbr->partition_record[protective_part].starting_chs[0] = 0;
	mbr->partition_record[protective_part].starting_chs[1] = 2;
	mbr->partition_record[protective_part].starting_chs[2] = 0;
	device_size_chs = device_size / STANDARD_BLOCKSIZE;
	if (device_size_chs > MAX_CYLINDERS * MAX_HEADS * MAX_SECTORS) {
		mbr->partition_record[protective_part].ending_chs[0] = 0xFF;
		mbr->partition_record[protective_part].ending_chs[1] = 0xFF;
		mbr->partition_record[protective_part].ending_chs[2] = 0xFF;
	} else {
		device_size_chs--;
		cylinder = device_size_chs / (MAX_HEADS * MAX_SECTORS);
		device_size_chs -= cylinder * MAX_HEADS * MAX_SECTORS;
		head = device_size_chs / MAX_SECTORS;
		sector = device_size_chs + 1 - head * MAX_SECTORS;
		mbr->partition_record[protective_part].ending_chs[0] = head;
		mbr->partition_record[protective_part].ending_chs[1] = sector | ((cylinder & 0x300) >> 2);
		mbr->partition_record[protective_part].ending_chs[2] = cylinder & 0xFF;
	}
	mbr->partition_record[protective_part].starting_lba = htole32(1);
	if (device_size - STANDARD_BLOCKSIZE > 0xFFFFFFFFull * block_size) {
		mbr->partition_record[protective_part].size_in_lba = htole32(0xFFFFFFFF);
	} else {
		mbr->partition_record[protective_part].size_in_lba = htole32((device_size - 1) / block_size);
	}

	/* Write out MBR */
	if ( lseek64(fd, 0, SEEK_SET) == (off64_t) -1 ) {
		fprintf(stderr,"Cannot seek to beginning of %s: %s (%d).\n", argv[1], strerror(errno), errno);
		free(mbr);
		close(fd);
		return 1;
	}
	if ( (rc = write(fd, mbr, block_size)) != block_size) {
		if (rc < 0) {
			fprintf(stderr,"Cannot write MBR: %s (%d).\n", strerror(errno), errno);
		} else {
			fputs("Short write while writing new MBR.\n", stderr);
		}
		free(mbr);
		close(fd);
		return 1;
	}
	puts("New MBR written.");
	free(mbr);

	/* Get primary GPT */
	if (lseek64(fd, block_size, SEEK_SET) == (off64_t) -1 ) {
		fprintf(stderr,"Cannot seek to beginning of first gpt header of %s: %s (%d).\n", argv[1], strerror(errno), errno);
		close(fd);
		return 1;
	}
	if ( (primary_gpt_header = malloc(block_size)) == NULL ) {
		fputs("Cannot allocate storage for primary gpt header.\n", stderr);
		close(fd);
		return 1;
	}
	if ( (rc = read(fd, primary_gpt_header, block_size)) != block_size ) {
		if (rc < 0) {
			fprintf(stderr, "Cannot read primary gpt header of %s: %s (%d).\n", argv[1], strerror(errno), errno);
		} else {
			fputs("Short read while reading primary gpt header.\n", stderr);
		}
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	/* Check magic, version and size of GPT header */
	if (memcmp(primary_gpt_header->header.signature, gpt_signature, sizeof(gpt_signature))) {
		fputs("The primary gpt header has a bad signature.\n", stderr);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}
	if (memcmp(primary_gpt_header->header.revision, gpt_revision, sizeof(gpt_revision))) {
		fputs("Unknown gpt header revision.\n", stderr);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}
	if ( (le32toh(primary_gpt_header->header.header_size) < 92) || (le32toh(primary_gpt_header->header.header_size) > block_size) ) {
		fprintf(stderr,"Bad gpt header size: %u bytes.\n", le32toh(primary_gpt_header->header.header_size));
		free(primary_gpt_header);
		close(fd);
		return 1;
	}
	if (le32toh(primary_gpt_header->header.size_of_partition_entry) != sizeof(t_gpt_record)) {
		fprintf(stderr,"Unsupported partition record size of %u.\n",le32toh(primary_gpt_header->header.size_of_partition_entry));
		free(primary_gpt_header);
		close(fd);
		return 1;
	}
	if (le32toh(primary_gpt_header->header.number_of_partition_entries) > MAX_PARTITION_ENTRYS) {
		fprintf(stderr,"Unsupported number of partition records: %u\n",le32toh(primary_gpt_header->header.number_of_partition_entries));
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	/* Check CRC32 of GPT header */
	crc = ul_crc32_exclude_offset(0xFFFFFFFF, primary_gpt_header->data, le32toh(primary_gpt_header->header.header_size),
	                              offsetof(t_gpt_header, header_crc32), sizeof(uint32_t)) ^ 0xFFFFFFFF;

	if (crc != le32toh(primary_gpt_header->header.header_crc32)) {
		fputs("Bad gpt crc checksum.\n", stderr);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	/* Load gpt partition table */
	if (lseek64(fd, block_size * le64toh(primary_gpt_header->header.partition_entry_lba), SEEK_SET) == (off64_t) -1) {
		fprintf(stderr,"Cannot seek to beginning of primary partition table of %s: %s (%d).\n", argv[1], strerror(errno), errno);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	partition_table_size = sizeof(t_gpt_record) * le32toh(primary_gpt_header->header.number_of_partition_entries);
	if (partition_table_size % block_size > 0) {
		partition_table_size = ((partition_table_size / block_size) + 1) * block_size;
	}
	if ( (partition_table = malloc(partition_table_size)) == NULL ) {
		fputs("Cannot allocate memory for primary partition table.\n", stderr);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	if ( ( rc = read(fd, partition_table, partition_table_size)) != partition_table_size) {
		if (rc < 0) {
			fprintf(stderr,"Cannot read primary partition table of %s: %s (%d).\n", argv[1], strerror(errno), errno);
		} else {
			fputs("Short read while reading primary partition table.\n", stderr);
		}
		free(partition_table);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	/* Check CRC of partition table */
	crc = ul_crc32(0xFFFFFFFF, partition_table->data, sizeof(t_gpt_record) * le32toh(primary_gpt_header->header.number_of_partition_entries)) ^ 0xFFFFFFFF;

	if (crc != le32toh(primary_gpt_header->header.partition_entry_array_crc32)) {
		fprintf(stderr,"Bad partition table checksum on %s.\n", argv[1]);
		free(partition_table);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	/* Calculate LBAs of new backup table */
	new_backup_gpt_lba = device_size / block_size - 1;
	if (new_backup_gpt_lba == le64toh(primary_gpt_header->header.alternate_lba)) {
		puts("GPT already fine.\n");
		free(partition_table);
		free(primary_gpt_header);
		close(fd);
		return 0;
	}

	if (new_backup_gpt_lba < le64toh(primary_gpt_header->header.alternate_lba)) {
		fputs("Looks like the disk size has been decreased!!\n", stderr);
		free(partition_table);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	new_backup_part_lba = new_backup_gpt_lba - partition_table_size / block_size;
	if (new_backup_part_lba <= le64toh(primary_gpt_header->header.alternate_lba)) {
		fputs("New backup GPT and old backup GPT overlap. This does not work.\n", stderr);
		free(partition_table);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	/* Write out new backup partition table */
	if ( lseek64(fd, new_backup_part_lba * block_size, SEEK_SET) == (off64_t) -1) {
		fprintf(stderr,"Cannot seek to position of new backup partition table: %s (%d).\n", strerror(errno), errno);
		free(partition_table);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}
	if ( (rc = write(fd, partition_table, partition_table_size)) != partition_table_size) {
		if (rc < 0) {
			fprintf(stderr, "Cannot write new backup partition table: %s (%d).\n", strerror(errno), errno);
		} else {
			fputs("Short write while writing new backup partition table.\n", stderr);
		}
		free(partition_table);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	free(partition_table);

	/* Create new backup gpt header */
	if ( (alternate_gpt_header = malloc(block_size)) == NULL ) {
		fputs("Cannot allocate storage for backup gpt header.\n", stderr);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	memcpy(alternate_gpt_header, primary_gpt_header, block_size);
	alternate_gpt_header->header.last_usable_lba = htole64(new_backup_part_lba - 1);
	alternate_gpt_header->header.my_lba = htole64(new_backup_gpt_lba);
	alternate_gpt_header->header.alternate_lba = htole64(1);
	alternate_gpt_header->header.partition_entry_lba = htole64(new_backup_part_lba);
	crc = ul_crc32_exclude_offset(0xFFFFFFFF, alternate_gpt_header->data, le32toh(alternate_gpt_header->header.header_size),
	                              offsetof(t_gpt_header, header_crc32), sizeof(uint32_t)) ^ 0xFFFFFFFF;
	alternate_gpt_header->header.header_crc32 = htole32(crc);

	/* Write alternate GPT header */
	if ( (rc = write(fd, alternate_gpt_header, block_size)) != block_size) {
		if (rc < 0) {
			fprintf(stderr, "Cannot write new backup GPT header: %s (%d).\n", strerror(errno), errno);
		} else {
			fputs("Short write while writing new backup GPT header.\n", stderr);
		}
		free(alternate_gpt_header);
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	free(alternate_gpt_header);
	puts("New backup GPT header and partition table written.");

	/* Update primary gpt header */
	old_backup_gpt_lba = le64toh(primary_gpt_header->header.alternate_lba);
	old_backup_part_lba = old_backup_gpt_lba - partition_table_size / block_size;

	primary_gpt_header->header.last_usable_lba = htole64(new_backup_part_lba - 1);
	primary_gpt_header->header.alternate_lba = htole64(new_backup_gpt_lba);

	crc = ul_crc32_exclude_offset(0xFFFFFFFF, primary_gpt_header->data, le32toh(primary_gpt_header->header.header_size),
	                              offsetof(t_gpt_header, header_crc32), sizeof(uint32_t)) ^ 0xFFFFFFFF;
	primary_gpt_header->header.header_crc32 = htole32(crc);

	if (lseek64(fd, block_size, SEEK_SET) == (off64_t) -1 ) {
		fprintf(stderr,"Cannot seek to beginning of first gpt header of %s: %s (%d).\n", argv[1], strerror(errno), errno);
		close(fd);
		return 1;
	}

	if ( (rc = write(fd, primary_gpt_header, block_size)) != block_size ) {
		if (rc < 0) {
			fprintf(stderr,"Cannot write new primary gpt header: %s /%d).\n", strerror(errno), errno);
		} else {
			fputs("Short write while writing new primary gpt header.\n", stderr);
		}
		free(primary_gpt_header);
		close(fd);
		return 1;
	}

	free(primary_gpt_header);
	puts("Updated primary GPT header written.");

	/* Wipe old alternate gpt partition table and header */
	if ( (zeroes = malloc(block_size + partition_table_size)) == NULL ) {
		fputs("Cannot allocate storage to wipe out old backup gpt data.\n", stderr);
		close(fd);
		return 1;
	}
	bzero(zeroes, block_size + partition_table_size);

	if (lseek64(fd, old_backup_part_lba * block_size, SEEK_SET) == (off64_t) -1 ) {
		fprintf(stderr,"Cannot seek to old backup gpt data.\n");
		close(fd);
		return 1;
	}

	if ( (rc = write(fd, zeroes, block_size + partition_table_size)) != block_size + partition_table_size) {
		if (rc < 0) {
			fprintf(stderr,"Cannot wipe out old backup gpt data: %s (%d).\n", strerror(errno), errno);
		} else {
			fputs("Short write while wiping out old backup gpt data.\n", stderr);
		}
		rc = 1;
	} else {
		rc = 0;
		puts("Old backup GPT header and partition table wiped out.");
	}

	free(zeroes);
	close(fd);

	return rc;
}

