# Provides the following functions to manipulate text files:
# - Add a section
# - Delete a section
# - Get all entries in a section
# - Add an entry in a section
# - Remove an entry from a section

SECTION_START_PREFIX='#START:'
SECTION_END_PREFIX='#END:'

# Add a section.
# 	$1 : File
# 	$2 : Section name
add_section() {
	is_section_present $1 $2
	if [ $? -eq 0 ]; then
		echo "Section $2 already exists"
		return 1
	fi

	local header=$(section_header $2)
	local footer=$(section_footer $2)
	printf "\n\n$header\n$footer\n" >> $1

	return 0
}

# Add a section.
# 	$1 : File
# 	$2 : Section name
delete_section() {
	is_section_present $1 $2
	if [ $? -ne 0 ]; then
		echo "Section $2 not found"
		return 1
	fi

	local header=$(section_header $2)
	local footer=$(section_footer $2)
	sed -r -i "/$header/,/$footer/ d" $1
	return 0
}

# Insert a line at the top of a section
#	$1: File
#	$2: Section name
#	$3: Line to insert
insert_top_of_section() {
	is_section_present $1 $2
	if [ $? -ne 0 ]; then
		echo "Section $2 not found"
		return 1
	fi

	local header=$(section_header $2)
	# The \\$3 is because if $3 starts with whitespaces but there is no \ before it, those whitespaces are not written to file.
	# The double backslash is because a single backslash is escape character for bash. We want to escape the backslash itself so 
	# that it gets passed as a backslash to sed.
	sed -r -i "/$header/ a \\$3" $1
	return 0
}

# Insert a line at the bottom of a section
#	$1: File
#	$2: Section name
#	$3: Line to insert
insert_bottom_of_section() {
	is_section_present $1 $2
	if [ $? -ne 0 ]; then
		echo "Section $2 not found"
		return 1
	fi

	local footer=$(section_footer $2)
	# The \\$3 is because if $3 starts with whitespaces but there is no \ before it, those whitespaces are not written to file.
	# The double backslash is because a single backslash is escape character for bash. We want to escape the backslash itself so 
	# that it gets passed as a backslash to sed.
	sed -r -i "/$footer/ i \\$3" $1
	return 0
}

# Replace matching lines inside a section.
#	$1: File
#	$2: Section name
#	$3: Pattern to match
#	$4: Replacement line
replace_line() {
	is_section_present $1 $2
	if [ $? -ne 0 ]; then
		echo "Section $2 not found"
		return 1
	fi

	local header=$(section_header $2)
	local footer=$(section_footer $2)

	# Important: The 'c $4' portion has to be the last thing on its line, and rest of the command has to be on newline.
	# Otherwise, it throws an "unmatched {" error.
	# The \\$4 is because if $4 starts with whitespaces but there is no \ before it, those whitespaces are not written to file.
	# The double backslash is because a single backslash is escape character for bash. We want to escape the backslash itself so 
	# that it gets passed as a backslash to sed.
	#sed -r -i "/$header/,/$footer/ {/$3/ c \\$4 
	#	}" $1
	# The /$3/ is changed to \|$3| - ie, the sed delimiter is changed from / to |
	# because $3 may itself contain / (slashes)
	sed -r -i "/$header/,/$footer/ {\|$3| c \\$4 
		}" $1
}

# Checks if matching line is present, and accordingly replaces or inserts.
#	$1: File
#	$2: Section name
#	$3: Search for existing line
#	$4: Line to insert or replace
insert_or_replace_in_section() {
	local contents
	contents=$(get_section $1 $2)
	echo "$contents" | grep -q "$3"
	local found=$?
	if [ $found -eq 1 ]; then
		echo "$3 not found in $1 section $2. inserting"
		insert_bottom_of_section $1 $2 "$4"
	else
		echo "$3 found in $1 section $2. replacing"
		replace_line $1 $2 "$3" "$4"
	fi
}

# Replaces a section completely with contents of another file.
# 	$1 : Target file
#	$2 : Section name
#	$3 : File to include into target file	
replace_section_with_file() {
	# Add section if it's not already present.
	add_section $1 $2

	local header=$(section_header $2)
	local footer=$(section_footer $2)
	# This sed means "between header and footer, print header, followed by contents of $3 file, then print footer, and delete
	# every line between header and footer.
	# The "r $3" has to be the last thing on its line to avoid "unmatched {" error
	sed -r -i "/$header/,/$footer/ {/$header/ {p; r $3
	}; /$footer/p; d}" $1
}

# Delete matching lines inside a section
#	$1: File
#	$2: Section name
#	$3: Pattern to delete
delete_line() {
	is_section_present $1 $2
	if [ $? -ne 0 ]; then
		echo "Section $2 not found"
		return 1
	fi

	local header=$(section_header $2)
	local footer=$(section_footer $2)
	sed -r -i "/$header/,/$footer/ {/$3/ d}" $1
}

# Gets all lines inside a section, excluding the section header and footer.
#	$1: File
#	$2: Section name
get_section() {
	is_section_present $1 $2
	if [ $? -ne 0 ]; then
		return 1
	fi
	local header=$(section_header $2)
	local footer=$(section_footer $2)
	# -n means don't print the entire search space, but only matched lines.
	sed -r -n "/$header/,/$footer/ {/$header/d;/$footer/d; p}" $1
}


# Check if a section already exists
# 	$1 : File
# 	$2 : Section name
is_section_present() {
	local sechdr=$(section_header $2)
	grep -q $sechdr $1
	return $?
}

# Form the section start header.
# 	$1 : Section name
section_header() {
	printf "$SECTION_START_PREFIX$1\n"
}

# Form the section end header.
# 	$1 : Section name
section_footer() {
	printf "$SECTION_END_PREFIX$1\n"
}




