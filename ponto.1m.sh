#!/bin/bash

# Bate o 'ponto' conforme a máquina entra/sai do estado idle.
# Só bate a saída quando o máquina está a mais de $INTERVALO_CONSIDERADO minutos idle.
# Também registra o último shutdown.
# O relatório fica em $PONTO_DIR.
# AVISO: Cuidado ao editar o arquivo do relatório.
# O último carectere não pode ser um \n (quebra de linha) senão buga =D.

# diretório onde os registros serão feitos
PONTO_DIR=$HOME/ponto

# tempo em que máquina ficou parada,
# considerado para registrar uma saida, em minutos
INTERVALO_CONSIDERADO=15

# exigir confirmação para registrar batidas com intervalo
# menor do que 1h
EXIGIR_CONFIRMACAO=no


last_event_path=$PONTO_DIR/.event

idle() {
    echo $((`ioreg -c IOHIDSystem | sed -e \
        '/HIDIdleTime/ !{ d' -e 't' -e '}' -e 's/.* = //g' -e 'q'` \
        / 1000000000))
}

save_event() {
    local t=
    if [[ "$1" == saida ]]; then
        t=`date -v-${INTERVALO_CONSIDERADO}M +'%H:%M'`
    else
        t=`date +'%H:%M'`
    fi
    local day=`date +'%Y-%m-%d'`
    confirm $1 $t $day && {
        register $t $day
        printf "$1 $t\n$day\n" | tee $last_event_path
    }
}

register() {
    local day=$2
    local m=${day:0:7}
    local d=${day:8}

    local file=$PONTO_DIR/$m.txt

    local line=$(tail -n1 $file 2>/dev/null)
    if [[ "$line" = *"$d - "* ]]; then
        printf ", %s" "$1" >> $file
    else
        printf "\n$d - $1" >> $file
    fi
}

tms() {
    date -j -f '%H:%M' "$1" +"%s"
}

confirm() {
    local event="$1"
    local time="$2"
    local d="$3"

    if [[ ! $EXIGIR_CONFIRMACAO == "yes" ]] || [[ "$event" == "saida" ]]; then
        return 0
    fi

    local last_event=`get_last_event`
    if [[ -z "$last_event" ]] || [[ ! "$last_event" = *"$d"* ]]; then
        return 0
    fi

    local l_time=`echo $last_event | cut -d' ' -f2`

    local last_time=`tms $l_time`
    local reg_time=`tms $time`
    local in_one_hour=$(( $last_time + 3540 ))

    if [[ $in_one_hour -lt $reg_time ]]; then
        rm -rf $PONTO_DIR/.delayed
        return 0
    fi

    [[ -e $PONTO_DIR/.delayed ]] || {
        local result=`osascript -e "display dialog \
            \"Intervalo menor do que 1h. \
            Última batida: $l_time. Agora: $time \
            Deseja registrar entrada?\" buttons {\"Sim\", \"Não\"} \
            default button \"Sim\""`

        if [[ "$result" = "button returned:Sim" ]]; then
            return 0
        fi
        touch $PONTO_DIR/.delayed
    }

    echo "entrada adiada"
    echo ---
    echo "entrada adiata até $(date -j -f '%s' $in_one_hour +'%H:%M')"
    return -1
}

last_shutdown() {
    local l=`last -1 shutdown | egrep -o '[A-Z].+'`
    date -v-"${l:0:3}" -v-"${l:4:3}" +"%Y-%m-%d ${l:11}"
}

register_last_shutdown() {
    local last_event="$1"

    local last_s=`last_shutdown`
    local last_date=${last_s:0:10}
    local last_time=${last_s:10}

    # only if last event has same date as last showdown
    # and last event is "entrada"
    if [[ ! "$last_event" = *"$last_date"* ]] || \
            [[ ! "$last_event" = *"entrada"* ]]; then

        return
    fi

    register $last_time $last_date
}

current_month_report_path() {
    echo $PONTO_DIR/$(date +'%Y-%m.txt')
}

last_month_report_path() {
    echo $PONTO_DIR/$(date -v-1m +'%Y-%m.txt')
}

get_last_event() {
    cat $last_event_path 2>/dev/null
}

latest_registers() {
    tail -n1 `current_month_report_path` 2>/dev/null | cut -d- -f2
}

remove_last_register() {
    echo "done"
}

menu() {
    echo ---
    echo `latest_registers`
    echo ---
    echo "Mês atual | href=file://`current_month_report_path`"
    [[ -e "`last_month_report_path`" ]] && echo "Último mês | href=file://`last_month_report_path`"
    echo ---
    echo "Relatórios | href=file://$PONTO_DIR"
    echo ---
    echo "Último evento (.event) | href=file://$last_event_path"
    echo "Remover último registro | bash=\"$0\" param1=--remove-last-register refresh=true terminal=false"
}

main() {
    mkdir -p $PONTO_DIR
    local last_event=`get_last_event`
    # is idle:
    if [[ `idle` -gt $(($INTERVALO_CONSIDERADO*60)) ]]; then
        if [[ "$last_event" = *"entrada"* ]]; then
            last_event=`save_event saida`
        fi
    else
    # is not idle:
        if [[ -z "$last_event" ]]; then
            last_event=`save_event entrada`
        elif [[ ! "$last_event" = *"$(date +'%Y-%m-%d')"* ]]; then
            register_last_shutdown "$last_event"
            last_event=`save_event entrada`
        elif [[ "$last_event" = *"saida"* ]]; then
            last_event=`save_event entrada`
        fi
    fi

    echo "$last_event" | head -n1
}

if [[ "$1" == "--remove-last-register" ]]; then
    remove_last_register
    exit
fi

main
menu

