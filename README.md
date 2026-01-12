Estou fazendo um case tecnico para uma vaga de emprego onde preciso construir um pipeline de dados do zero para isso vou usar o terraform para criar a infraestrutura que preciso com e estabelecer um limite de custo de 15 dolares dentro do AWS Budgets e quando chegar o limite vou apenas destruir toda a infraestrutura. 

Deixei anexado o PDF das especificações para mais contexto. Para esse pipeline em específico vamos usar terraform,python,pyspark,glue,lambda,stepfunctions,redshift e s3 como mostra a imagem da arquitetura simples. 

Os artefatos a serem desenvolvidos serão:

- lambda com python requests para extrair dados da api OpenWeather e depositar no bucket s3 (datalake/bronze),
- 1 buckets s3 com os caminhos datalake/bronze e datalake/silver
- Glue com pyspark para etl e extrair o dado da bronze para a silver fazendo a limpeza dos dados e da silver para a gold 
- A tabela gold vai ser uma tabela redshift serverless
- para orquestra vamos usar o stepfunctions
- Vamos usa o github para subir esse código da infra e o código do ETL tanto para criar o ambiente quanto para os codigos das transformações 

Para isso preciso que me forneça um passo a passo com esse codigos e uma estrtura de pasta do projeto que eu vou usar para subir o projeto para o github