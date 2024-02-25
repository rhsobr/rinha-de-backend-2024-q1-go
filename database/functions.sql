CREATE
OR REPLACE VIEW extratos AS
SELECT
    cl.id,
    cl.saldo AS s,
    cl.limite AS l,
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
    ) AS ultimas
FROM
    clientes cl;

CREATE
OR REPLACE FUNCTION atualiza_saldo(
    cliente_id_p INTEGER,
    tipo_p CHAR,
    valor_p INTEGER,
    descricao_p VARCHAR
) RETURNS TABLE (s INTEGER, l INTEGER) AS $as$ BEGIN
    RETURN QUERY
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
        ) RETURNING saldo AS s,
        limite AS l;

END;

$as$ LANGUAGE plpgsql;

CREATE
OR REPLACE FUNCTION adiciona_transacao() RETURNS TRIGGER AS $t$ BEGIN
    WITH transacao_velha AS (
        SELECT
            (
                CASE
                    WHEN id = 10 THEN 1
                    ELSE id + 1
                END
            ) AS id
        FROM
            transacoes
        WHERE
            cliente_id = NEW .id
        ORDER BY
            realizada_em DESC
        LIMIT
            1
    )
    INSERT INTO
        transacoes (
            cliente_id,
            valor,
            tipo,
            descricao,
            id,
            realizada_em
        )
    VALUES
        (
            NEW .id,
            ABS(OLD .saldo - NEW .saldo),
            CASE
                WHEN OLD .saldo > NEW .saldo THEN 'd'
                ELSE 'c'
            END,
            NEW .descricao_saldo_atual,
            (
                SELECT
                    (
                        CASE
                            WHEN EXISTS(
                                SELECT
                                    1
                                FROM
                                    transacao_velha
                            ) THEN (
                                SELECT
                                    id
                                FROM
                                    transacao_velha
                            )
                            ELSE 1
                        END
                    ) AS id
            ),
            CLOCK_TIMESTAMP()
        ) ON CONFLICT (id, cliente_id) DO
    UPDATE
    SET
        (
            valor,
            tipo,
            descricao,
            realizada_em
        ) = (
            excluded.valor,
            excluded.tipo,
            excluded.descricao,
            excluded.realizada_em
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