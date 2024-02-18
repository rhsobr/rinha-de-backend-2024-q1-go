CREATE
OR REPLACE FUNCTION gera_extrato(cliente_id_p INTEGER) RETURNS JSON AS $ge$
DECLARE
    RESULT JSON;

BEGIN
    SELECT
        JSON_BUILD_OBJECT(
            'saldo',
            (
                COALESCE(
                    JSON_BUILD_OBJECT(
                        'total',
                        cl.saldo,
                        'limite',
                        cl.limite,
                        'data_extrato',
                        to_char (
                            NOW(),
                            'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
                        )
                    ),
                    NULL :: JSON
                )
            ),
            'ultimas_transacoes',
            (
                SELECT
                    COALESCE(JSON_AGG(line), '[]' :: JSON)
                FROM
                    (
                        SELECT
                            JSON_BUILD_OBJECT(
                                'valor',
                                t.valor,
                                'tipo',
                                t.tipo,
                                'descricao',
                                t.descricao,
                                'realizada_em',
                                to_char (t.realizada_em, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
                            ) AS line
                        FROM
                            transacoes AS t
                        WHERE
                            t.cliente_id = cl.id
                        ORDER BY
                            t.realizada_em DESC
                        LIMIT
                            10
                    ) AS _
            )
        ) INTO RESULT
    FROM
        clientes cl
    WHERE
        id = cliente_id_p;

RETURN RESULT;

END;

$ge$ LANGUAGE plpgsql;

CREATE
OR REPLACE FUNCTION atualiza_saldo(
    cliente_id_p INTEGER,
    tipo_p CHAR,
    valor_p INTEGER,
    descricao_p VARCHAR
) RETURNS JSON AS $as$
DECLARE
    RESULT JSON;

BEGIN
    UPDATE
        clientes cl
    SET
        descricao_saldo_atual = descricao_p,
        saldo = saldo + (
            valor_p * (
                CASE
                    WHEN tipo_p = 'd' THEN -1
                    ELSE 1
                END
            )
        )
    WHERE
        (
            cl.id = cliente_id_p
            AND (
                tipo_p = 'c'
                OR (cl.saldo - valor_p) >= (cl.limite * -1)
            )
        ) RETURNING COALESCE(
            JSON_BUILD_OBJECT('saldo', saldo, 'limite', limite),
            NULL :: JSON
        ) INTO RESULT;

RETURN RESULT;

END;

$as$ LANGUAGE plpgsql;

CREATE
OR REPLACE FUNCTION adiciona_transacao() RETURNS TRIGGER AS $t$ BEGIN
    INSERT INTO
        transacoes (cliente_id, valor, tipo, descricao)
    VALUES
        (
            NEW .id,
            ABS(OLD .saldo - NEW .saldo),
            CASE
                WHEN OLD .saldo > NEW .saldo THEN 'd'
                ELSE 'c'
            END,
            NEW .descricao_saldo_atual
        );

RETURN NEW;

END;

$t$ LANGUAGE plpgsql;

CREATE
OR REPLACE TRIGGER trigger_adiciona_transacao AFTER
UPDATE
    ON clientes FOR EACH ROW
    WHEN (
        OLD .saldo IS DISTINCT
        FROM
            NEW .saldo
    ) EXECUTE FUNCTION adiciona_transacao();