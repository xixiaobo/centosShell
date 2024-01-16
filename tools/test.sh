ARCH="test"
declare -A config
function compilation_parsing_value() {
    local txt=$1
    escape_slash_text="${txt//\\/\\\\}"
    escape_double_quotation_marks_text=${escape_slash_text//\"/\\\"}
    escape_dollar_sign_text=${escape_double_quotation_marks_text//\\\$/\\\\$}
    compile_text_to_value=$(eval "echo ${escape_dollar_sign_text}")
    escape_slash_value="${compile_text_to_value//\\/\\\\}"
    escape_double_quotation_marks_value=${escape_slash_value//\"/\\\"}
    escape_dollar_sign_value=${escape_double_quotation_marks_value//\\\$/\\\\$}
    echo "${escape_dollar_sign_value}"
}
file="test.conf"

while IFS= read -r line; do
  if [[ "$line" =~ ^\s*(#|;) ]]; then
      continue
  fi
  if [[ "$line" =~ ^\[work:(.*)\]$ ]]; then
      section="${BASH_REMATCH[1]}"
      if [[ "${config["$section|configPath"]}" ]]; then
         echo -e "\033[31m 项目 ${section} 配置出现多个配置，请在以下配置文件中检查配置！ \033[0m" >&2
         echo -e "\033[31m \t\t - 1: ${config["$section|configPath"]} \033[0m" >&2
         echo -e "\033[31m \t\t - 2: ${file} \033[0m" >&2
         exit 1
      fi
#      config["$section|configPath"]="$file"
  elif [[ "$line" =~ (.*)=(.*) ]]; then
    if [ -n "${section}" ]; then
      IFS="=" read -r key txt <<< "$line"
      config["$section|$key"]="$(compilation_parsing_value "${txt}")"
    fi
  fi
done  < "$file"
for key in "${!config[@]}"; do
 echo "${key} ---  ${config[${key}]}"
done
