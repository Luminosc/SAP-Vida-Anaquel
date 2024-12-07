--Parte Completa
DECLARE @EndDate DATE = '2010-12-31';

DECLARE @Numero VARCHAR(25) = 'A00001';
DECLARE @StartDate DATE = (SELECT MIN(DOCDATE) FROM OINM WHERE ItemCode = @Numero);
DECLARE @Inicio DATE = '2010-12-01';
DECLARE @Fin DATE = @EndDate;
-- Generador de días
WITH DateRange AS (
    SELECT @StartDate AS DateValue
    UNION ALL
    SELECT DATEADD(DAY, 1, DateValue)
    FROM DateRange
    WHERE DateValue <= @EndDate
),
InData AS(
    SELECT T0.DocDate,
                T0.ItemCode,
                T0.TransType,
                T0.CalcPrice,
           ROW_NUMBER() over (ORDER BY T0.DocDate) AS rn 
    FROM OINM AS T0
    WHERE T0.ItemCode = @Numero
    AND T0.TransType IN (15,13)
    AND T0.DocDate between @Inicio AND @EndDate
      AND T0.CalcPrice <> 0
),
--Subconsulta para obtener los datos de salida
OutData AS(
    SELECT T0.DocDate,
                T0.ItemCode,
                T0.TransType,
                T0.CalcPrice,
           ROW_NUMBER() over (ORDER BY T0.DocDate) AS rn 
    FROM OINM AS T0
    WHERE T0.ItemCode = @Numero
    AND T0.TransType IN (14,16)
    AND T0.DocDate between @Inicio AND @EndDate
      AND T0.CalcPrice <> 0
),
-- Subconsulta de días con el último valor de CalcPrice distinto de cero
LastCalcPrice AS (
    SELECT T0.ItemCode, 
           T0.DocDate, 
           T0.CalcPrice,
           ROW_NUMBER() OVER (PARTITION BY T0.ItemCode, T0.DocDate ORDER BY T0.DocDate DESC) AS rn
    FROM OINM T0
    WHERE T0.ItemCode = @Numero 
      AND T0.DocDate <= @EndDate 
      AND T0.CalcPrice <> 0
),
FINALDAYS AS (-- Datos finales
SELECT 
    T0.DateValue,
    T1.ItemCode,
    ISNULL(SUM(T1.InQty), 0) AS TotalInQty,
    ISNULL(SUM(T1.OutQty), 0) AS TotalOutQty,
    ISNULL(SUM(T1.InQty), 0) - ISNULL(SUM(T1.OutQty), 0) AS Stock,
    ISNULL(T2.CalcPrice, 0) AS CalcPrice
FROM 
    DateRange T0 
LEFT JOIN OINM T1 
    ON T0.DateValue >= T1.DocDate 
    AND T1.ItemCode = @Numero 
LEFT JOIN LastCalcPrice T2 
    ON T0.DateValue = T2.DocDate 
    AND T1.ItemCode = T2.ItemCode 
    AND T2.rn = 1  -- Solo el último valor distinto de cero para cada día
GROUP BY 
    T0.DateValue, T1.ItemCode
, T2.CalcPrice),
DATETotal AS (
SELECT T0.DateValue,
    T0.ItemCode,
    T0.TotalInQty,
    T0.TotalOutQty,
    T0.Stock,
--    T0.CalcPrice
    CASE WHEN T0.CalcPrice = 0 THEN (SELECT TOP(1) T1.CalcPrice FROM FINALDAYS T1 WHERE T1.DateValue < T0.DateValue AND T1.CalcPrice <> 0 ORDER BY T1.DateValue DESC)
    ELSE T0.CalcPrice END AS CalcPrice 
FROM FINALDAYS T0),

DatePromedio AS (
SELECT T0.DateValue,
            T0.ItemCode,
            T0.TotalInQty,
            T0.TotalOutQty,
            T0.Stock,
            AVG (T0.Stock) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DateValue), DATEPART(MONTH, T0.DateValue) ORDER BY T0.DateValue ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as Promedio,
           T0.CalcPrice,
           T0.CalcPrice * T0.Stock as PrecioCalculo
FROM DATETotal T0
WHERE T0.DateValue between @Inicio AND @EndDate
GROUP BY T0.DateValue, T0.ItemCode, T0.TotalInQty, T0.TotalOutQty, T0.Stock, T0.CalcPrice
),
DateProm AS(
SELECT T0.DateValue,
            T0.ItemCode,
            T0.TotalInQty,
            T0.TotalOutQty,
            T0.Stock,
            T0.Promedio,
           T0.CalcPrice,
           AVG(T0.PrecioCalculo) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DateValue), DATEPART(MONTH, T0.DateValue) ORDER BY T0.DateValue ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as PrecioPromedio
FROM DatePromedio T0
GROUP BY T0.DateValue, T0.ItemCode, T0.TotalInQty, T0.TotalOutQty, T0.Stock, T0.CalcPrice, T0.Promedio,T0.CalcPrice, T0.PrecioCalculo
),
MONTHSDATA AS (
SELECT DISTINCT T0.DateValue,
            T0.ItemCode, 
            LAST_VALUE(T0.TotalInQty) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DateValue), DATEPART(MONTH, T0.DateValue) ORDER BY T0.DateValue ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS UltimaEntrada,    
          LAST_VALUE(T0.TotalOutQty) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DateValue), DATEPART(MONTH, T0.DateValue) ORDER BY T0.DateValue ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS UltimaSalida,   
          LAST_VALUE(T0.Stock) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DateValue), DATEPART(MONTH, T0.DateValue) ORDER BY T0.DateValue ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS UltimoStock,
          LAST_VALUE(T0.Promedio) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DateValue), DATEPART(MONTH, T0.DateValue) ORDER BY T0.DateValue ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS UltimoPromedio,
LAST_VALUE(T0.PrecioPromedio) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DateValue), DATEPART(MONTH, T0.DateValue) ORDER BY T0.DateValue ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS UltimoPrecio

FROM DateProm T0
GROUP BY T0.DateValue, T0.ItemCode, T0.TotalInQty, T0.TotalOutQty, T0.Stock, T0.Promedio, T0.PrecioPromedio
),
ULTIMATEDATE AS (
SELECT T0.ItemCode,
            T0.DateValue,
            T0.UltimaEntrada,
            T0.UltimaSalida,
            T0.UltimoStock as Stock,
            T0.UltimoPromedio as Promedio,
            T0.UltimoPrecio as PrecioProm
FROM MONTHSDATA T0
GROUP BY T0.DateValue, T0.ITEMCODE, T0.ULTIMAENTRADA, T0.ULTIMASALIDA, T0.UltimoStock, T0.UltimoPromedio, T0.UltimoPrecio
),
--Calculo final de los datos con promedio de precio
FINALDATAPRICE AS(
SELECT DISTINCT FORMAT(T0.DateValue,'yyyy/MM') AS DateValue,
            T0.ItemCode, 
            T1.ItemName,
            LAST_VALUE(T0.UltimaEntrada) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DateValue), DATEPART(MONTH, T0.DateValue) ORDER BY T0.DateValue ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS Entrada,    
            LAST_VALUE(T0.UltimaSalida) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DateValue), DATEPART(MONTH, T0.DateValue) ORDER BY T0.DateValue ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS Salida,
            LAST_VALUE(T0.Stock) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DateValue), DATEPART(MONTH, T0.DateValue) ORDER BY T0.DateValue ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS Stock,
            LAST_VALUE(T0.Promedio) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DateValue), DATEPART(MONTH, T0.DateValue) ORDER BY T0.DateValue ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS [Promedio de Stock],
LAST_VALUE(T0.PrecioProm) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DateValue), DATEPART(MONTH, T0.DateValue) ORDER BY T0.DateValue ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS [Promedio del precio]
FROM ULTIMATEDATE T0
JOIN OITM T1
ON T0.ItemCode = T1.ItemCode
--WHERE T0.DateValue between @Inicio AND @Fin
GROUP BY T0.DATEVALUE, T0.ITEMCODE, T0.ULTIMAENTRADA, T0.ULTIMASALIDA, T0.PROMEDIO, T0.stock, T0.PrecioProm, T1.ItemName
),
--Integracion de los datos por entradas y salidas en suma por meses (Aun salen repetidos)
IntePrices AS(
SELECT FORMAT(T0.DocDate,'yyyy/MM') AS InDAte,
                           T0.ItemCode AS InItemCode,
                             T0.TransType AS InTransType,
                            ISNULL(SUM(T0.CalcPrice) OVER (PARTITION BY T0.ItemCode, DATEPART(YEAR, T0.DocDate), DATEPART(MONTH,T0.DocDate ) ORDER BY T0.DocDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING),0) AS SuMInTrans,
                           FORMAT(T1.DocDate,'yyyy/MM') AS OutDate,
                           T1.ItemCode AS OutItemCode,
                             T1.TransType AS OutTransType,
                            ISNULL(SUM(T1.CalcPrice) OVER (PARTITION BY T1.ItemCode, DATEPART(YEAR, T1.DocDate), DATEPART(MONTH,T1.DocDate ) ORDER BY T1.DocDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING),0) AS SumOutTrans
FROM InData T0
FULL OUTER JOIN OutData T1
ON FORMAT(T0.DocDate,'yyyy/MM') = FORMAT(T1.DocDate,'yyyy/MM')
GROUP BY T0.DocDate,T0.ItemCode,T0.TransType,T0.CalcPrice, T1.DocDate,T1.ItemCode,T1.TransType, T1.CalcPrice
),
--Calculo final mensual para el promedio de costo 
FINALCOSTO AS(
SELECT DISTINCT T0.InDAte AS DateValue,
            T0.InItemCode AS ItemCode,
            SUM(T0.SuMInTrans) OVER (PARTITION BY T0.InItemCode, T0.InDate ORDER BY T0.InDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) - SUM(T0.SuMOutTrans) OVER (PARTITION BY T0.OutItemCode, T0.OutDate ORDER BY T0.OutDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS PromedioPrice
FROM IntePrices T0
where T0.InDAte >= FORMAT(@Inicio,'yyyy/MM')
)


SELECT T0.DateValue,
            T0.ItemCode, 
            T0.ItemName,
            T0.[Promedio del precio] AS PromedioValor,
            ISNULL(T1.PromedioPrice,0) AS CostoVentas,
            T1.PromedioPrice/T0.[Promedio del precio] Utilidad
FROM FINALDATAPRICE T0
LEFT JOIN FINALCOSTO T1
On T0.DateValue = T1.DateValue
OPTION (MAXRECURSION 0);