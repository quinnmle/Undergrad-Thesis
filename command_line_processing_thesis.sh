
# Downloading SRA toolikit
# download the gzip file
wget https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/2.9.1-1/sratoolkit.2.9.1-1-centos_linux64.tar.gz
# unzip the file
tar -xzvf sratoolkit.2.9.1-1-centos_linux64.tar.gz
# add the 'bin' directory to the PATH - note the you will need to do this


# everytime you start a new terminal and wish to use the toolkit

export PATH=$PWD/sratoolkit.2.9.1-1-centos_linux64/bin/:${PATH}

# Fetching SRA files
mkdir data
prefetch --option-file accessions.txt --output-directory ~/data

# Confirm all files
vdb-validate data/*

# Converting SRA to fastq
mkdir -p fastq tmp
for acc in ~/data/SRR*/; do
  acc=${acc%/}
  echo "Converting $acc"
  fasterq-dump --split-3 -e 8 -O fastq -t tmp "$acc"
done
rm -r tmp

# Confirm number of files are correct
ls fastq | wc -l

# Get fastqc
wget https://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v0.12.1.zip
unzip fastqc_v0.12.1.zip
cd FastQC
chmod +x fastqc
export PATH=$PATH:$(pwd)
cd ..

# QC raw reads
mkdir -p qc_raw
fastqc -t 16 -o qc_raw fastq/*.fastq

# Check
ls qc_raw | wc -l

# Get reference
mkdir -p ref && cd ref

# Genome (primary assembly)
wget -O genome.fa.gz \
  "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_48/GRCh38.primary_assembly.genome.fa.gz"

# Gene annotation (primary assembly)
wget -O genes.gtf.gz \
  "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_48/gencode.v48.primary_assembly.annotation.gtf.gz"

gunzip -f genome.fa.gz
gunzip -f genes.gtf.gz

cd ..

# Get STAR or go to path
export PATH=$PATH:$(pwd)

# Build STAR genome index
mkdir -p ref/star_index
STAR --runThreadN 16 \
  --runMode genomeGenerate \
  --genomeDir ref/star_index \
  --genomeFastaFiles ref/genome.fa \
  --sjdbGTFfile ref/genes.gtf \
  --sjdbOverhang 149



# Align with STAR
mkdir -p bam
for r1 in fastq/*_1.fastq; do
  r2="${r1%_1.fastq}_2.fastq"
  base=$(basename "$r1" _1.fastq)

  STAR --runThreadN 16 \
    --genomeDir ref/star_index \
    --readFilesIn "$r1" "$r2" \
    --outFileNamePrefix "bam/${base}_" \
    --outSAMtype BAM SortedByCoordinate
done

# Indexing BAMs using samtools
for bam_file in bam/*_Aligned.sortedByCoord.out.bam; do
  echo "Indexing $bam_file"
  samtools index "$bam_file"
done



#-----------# Generating Count Matrix #-----------#

wget https://sourceforge.net/projects/subread/files/subread-2.0.5/subread-2.0.5-Linux-x86_64.tar.gz
tar -xzf subread-2.0.5-Linux-x86_64.tar.gz

export PATH=$PWD/subread-2.0.5-Linux-x86_64/bin:$PATH

featureCounts -v

featureCounts -T 8 \
  -p --countReadPairs \
  -t exon \
  -g gene_id \
  -a ref/genes.gtf \
  -o results/counts.txt \
  bam/*_Aligned.sortedByCoord.out.bam

#-----------# #-----------# #-----------# #-----------#

featureCounts -T 16 -p -B -C -s 2 \
  -a ref/gencode.v42.annotation.gtf \
  -o gene_counts.txt \
  bam/*_Aligned.sortedByCoord.out.bam
