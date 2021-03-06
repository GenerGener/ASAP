
args = commandArgs(trailingOnly=TRUE)

if (0==length(args)) {
    cat("This script processes the TSV file generated by AnnotSV, and extract essential annotations like rank.
To run the script, pass in
   the original vcf as the first argument,
   the desired output VCF as the second argument,
   and the annotated TSV from AnnotSV as the third argument.\n")
    quit(save = "no")
}
original.vcf = args[1]
output.vcf = args[2]
input.tsv.file = args[3]

# load the annotated TSV from AnnotSV
annotated.tsv = read.delim(input.tsv.file, stringsAsFactors = F)
if ("FORMAT" %in% names(annotated.tsv)) {
    sample.name = names(annotated.tsv)[14]
    offset = 14
} else {
    offset = 12
    sample.name = NA
}

# QC that no annotation has illegal characters
ok.annotations = NULL
has.semicoln = NULL
has.comma = NULL
has.space = NULL
for (i in c((offset+1):ncol(annotated.tsv))) {
    a = length( grep(";", annotated.tsv[,i]) )
    b = length( grep(",", annotated.tsv[,i]) )
    c = length( grep(" ", annotated.tsv[,i]) )
    if(0==(a+b+c)) {
        ok.annotations = c(ok.annotations, names(annotated.tsv)[i])
    } else if (0==(a+b)) {
        has.space = c(has.space, names(annotated.tsv)[i])
    } else if (0==(b+c)) {
        has.semicoln = c(has.semicoln, names(annotated.tsv)[i])
    } else if (0==(c+a)) {
        has.comma = c(has.comma, names(annotated.tsv)[i])
    }
}

if (!all(c("AnnotSV.ranking", "Gene.name", "promoters", "ACMG") %in% ok.annotations))
    stop("key annotations to extract contains illegal characters as defined by VCF spec")

# merge the lines that have the same AnnotSV.ID
if (is.na(sample.name)) {
    resulting.vcf = data.frame("CHROM" = character(0),
                               "POS" = numeric(0),
                               "ID" = character(0),
                               "REF" = character(0),
                               "ALT" = character(0),
                               "QUAL" = numeric(0),
                               "FILTER" = character(0),
                               "INFO" = character(0),
                               stringsAsFactors = F)
} else {
    resulting.vcf = data.frame("CHROM" = character(0),
                               "POS" = numeric(0),
                               "ID" = character(0),
                               "REF" = character(0),
                               "ALT" = character(0),
                               "QUAL" = numeric(0),
                               "FILTER" = character(0),
                               "INFO" = character(0),
                               "FORMAT" = character(0),
                               sample.name = character(0),
                               stringsAsFactors = F)
}

unique.ids = unique(annotated.tsv$"AnnotSV.ID")
for(i in c(1:length(unique.ids))) {
    if (0 == (i %% 1000)) print(i)
    id = unique.ids[i]
    df = annotated.tsv[grepl(id, annotated.tsv$"AnnotSV.ID", fixed = T), ]
    chr = unique(df$"SV.chrom"[1])
    pos = unique(df$"SV.start"[1])
    id = unique(df$"ID"[1])
    ref = unique(df$"REF"[1])
    alt = unique(df$"ALT"[1])
    qual = unique(df$"QUAL"[1])
    filter = unique(df$"FILTER"[1])

    original.info = df$"INFO"[1]
    rank = df$"AnnotSV.ranking"[1]
    af = unique(df$'GD_AF'[1])

    if (any("" != unique(df$"ACMG"))) {
        gene = paste(unique(df["" != unique(df$"ACMG"), 'Gene.name']),
                     collapse = ",")
        extra.info = paste(paste0("ANNOTSVRANK=", rank),
                           paste0("ACMG_GENE=", gene),
                           paste0("GD_AF=", af),
                           sep = ";")
    } else {
        extra.info = paste(paste0("ANNOTSVRANK=", rank),
                           paste0("GD_AF=", af),
                           sep = ";")
    }
    info = paste(original.info, extra.info, sep = ";")

    if ( !is.na(sample.name) ) {
        format = unique(df$"FORMAT"[1])
        sp = df[1, offset]
        resulting.vcf[i,] = c(chr, pos, id, ref, alt, qual, filter, info,
                              format, sp)
    } else {
        resulting.vcf[i,] = c(chr, pos, id, ref, alt, qual, filter, info)
    }
}

old.header = readLines(original.vcf, n = 5000)
old.header = old.header[grep("^##", old.header)]
rank.header = "##INFO=<ID=ANNOTSVRANK,Number=.,Type=String,Description=\"Rank as given by AnnotSV\">"
acmg.header = "##INFO=<ID=ACMG_GENE,Number=.,Type=String,Description=\"ACMG gene annotation as given by AnnotSV\">"
af.header = "##INFO=<ID=GD_AF,Number=1,Type=Float,Description=\"Maximum of the gnomAD allele frequency (for biallelic sites) and copy-state frequency (for multiallelic sites)\">"
new.info.header.lines = c(rank.header, acmg.header, af.header)
idx = max(grep("INFO", old.header))
new.header = append(x = old.header, values = new.info.header.lines, after = idx)

fileConn = file(output.vcf)
writeLines(text = new.header, fileConn)
close(fileConn)

names(resulting.vcf)[1] = "#CHROM"
if (!is.na(sample.name))
    names(resulting.vcf)[10] = sample.name
write.table(resulting.vcf, file = output.vcf,
            append = T,
            sep = "\t", quote = F, row.names = F)
