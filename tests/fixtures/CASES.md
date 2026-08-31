# Fixture cases — readable listing

Work the expected figures out from this by hand. Do not compute them
with the SQL you are testing; that would prove nothing.

## Application_919038062
*simple path - one offer, accepted* — 22 events

```
timestamp                  activity                   lifecycle  resource
2016-03-30 11:14:36.932    A_Create Application       complete   User_87
2016-03-30 11:14:36.935    A_Concept                  complete   User_87
2016-03-30 11:14:36.940    W_Complete application     schedule   User_87
2016-03-30 11:14:36.944    W_Complete application     start      User_87
2016-03-30 11:19:39.364    A_Accepted                 complete   User_87
2016-03-30 11:24:02.618    O_Create Offer             complete   User_87
2016-03-30 11:24:04.737    O_Created                  complete   User_87
2016-03-30 11:25:10.569    O_Sent (online only)       complete   User_87
2016-03-30 11:25:10.613    W_Complete application     complete   User_87
2016-03-30 11:25:10.631    W_Call after offers        schedule   User_87
2016-03-30 11:25:10.635    W_Call after offers        start      User_87
2016-03-30 11:25:10.638    A_Complete                 complete   User_87
2016-03-30 11:25:17.286    W_Call after offers        complete   User_87
2016-03-30 11:25:17.293    W_Validate application     schedule   User_87
2016-03-30 11:25:17.295    W_Validate application     start      User_87
2016-03-30 11:25:18.154    A_Validating               complete   User_87
2016-03-30 11:25:22.498    O_Returned                 complete   User_87
2016-03-30 11:30:45.926    W_Validate application     suspend    User_87
2016-03-30 15:21:16.759    W_Validate application     resume     User_87
2016-03-30 15:21:47.634    O_Accepted                 complete   User_87
2016-03-30 15:21:47.638    A_Pending                  complete   User_87
2016-03-30 15:21:47.646    W_Validate application     complete   User_87
```

## Application_2098856182
*two offers, cancelled* — 13 events

```
timestamp                  activity                   lifecycle  resource
2016-03-03 16:31:41.007    A_Create Application       complete   User_23
2016-03-03 16:31:41.016    W_Complete application     schedule   User_23
2016-03-03 16:31:41.018    W_Complete application     start      User_23
2016-03-03 16:31:41.020    A_Concept                  complete   User_23
2016-03-03 16:33:12.953    A_Accepted                 complete   User_23
2016-03-03 16:38:26.709    O_Create Offer             complete   User_23
2016-03-03 16:38:27.984    O_Created                  complete   User_23
2016-03-03 16:38:46.843    O_Create Offer             complete   User_23
2016-03-03 16:38:48.067    O_Created                  complete   User_23
2016-03-03 16:49:24.538    A_Cancelled                complete   User_23
2016-03-03 16:49:24.572    O_Cancelled                complete   User_23
2016-03-03 16:49:24.581    O_Cancelled                complete   User_23
2016-03-03 16:49:24.595    W_Complete application     complete   User_23
```

## Application_323048075
*rework - an A_ activity repeats, denied* — 30 events

```
timestamp                  activity                   lifecycle  resource
2016-01-13 14:38:17.368    A_Create Application       complete   User_95
2016-01-13 14:38:17.394    A_Concept                  complete   User_95
2016-01-13 14:38:17.422    W_Complete application     schedule   User_95
2016-01-13 14:38:17.425    W_Complete application     start      User_95
2016-01-13 14:49:01.554    A_Accepted                 complete   User_95
2016-01-13 14:51:49.849    O_Create Offer             complete   User_95
2016-01-13 14:51:50.968    O_Created                  complete   User_95
2016-01-13 14:52:10.312    O_Sent (online only)       complete   User_95
2016-01-13 14:52:10.326    W_Complete application     complete   User_95
2016-01-13 14:52:10.333    W_Call after offers        schedule   User_95
2016-01-13 14:52:10.335    W_Call after offers        start      User_95
2016-01-13 14:52:10.337    A_Complete                 complete   User_95
2016-01-13 14:52:14.835    W_Call after offers        complete   User_95
2016-01-13 14:52:14.840    W_Validate application     schedule   User_95
2016-01-13 14:52:14.842    W_Validate application     start      User_95
2016-01-13 14:52:15.703    A_Validating               complete   User_95
2016-01-13 14:55:59.615    W_Validate application     complete   User_95
2016-01-13 14:55:59.620    W_Call incomplete files    schedule   User_95
2016-01-13 14:55:59.622    W_Call incomplete files    start      User_95
2016-01-13 14:55:59.624    A_Incomplete               complete   User_95
2016-01-13 14:56:30.091    W_Call incomplete files    suspend    User_95
2016-01-14 10:09:33.796    W_Call incomplete files    resume     User_2
2016-01-14 10:12:27.354    W_Call incomplete files    suspend    User_2
2016-01-14 11:30:10.350    W_Call incomplete files    ate_abort  User_44
2016-01-14 11:30:10.358    W_Validate application     schedule   User_44
2016-01-14 11:30:10.360    W_Validate application     start      User_44
2016-01-14 11:30:10.504    A_Validating               complete   User_44
2016-01-14 11:35:47.849    A_Denied                   complete   User_44
2016-01-14 11:35:47.874    O_Refused                  complete   User_44
2016-01-14 11:35:47.884    W_Validate application     complete   User_44
```

## Application_682602203
*aborted work item, cancelled* — 11 events

```
timestamp                  activity                   lifecycle  resource
2016-07-14 15:07:09.102    A_Create Application       complete   User_40
2016-07-14 15:07:09.122    W_Complete application     schedule   User_40
2016-07-14 15:07:09.128    W_Complete application     start      User_40
2016-07-14 15:07:09.134    A_Concept                  complete   User_40
2016-07-14 15:13:19.498    A_Accepted                 complete   User_40
2016-07-14 15:15:54.822    O_Create Offer             complete   User_40
2016-07-14 15:15:55.624    O_Created                  complete   User_40
2016-07-14 15:17:00.303    W_Complete application     suspend    User_40
2016-07-14 15:23:17.661    A_Cancelled                complete   User_40
2016-07-14 15:23:17.683    O_Cancelled                complete   User_40
2016-07-14 15:23:17.694    W_Complete application     ate_abort  User_40
```

## Application_1291275220
*right-censored - no terminal state* — 18 events

```
timestamp                  activity                   lifecycle  resource
2016-12-30 14:44:13.619    A_Create Application       complete   User_1
2016-12-30 14:44:14.682    A_Submitted                complete   User_1
2016-12-30 14:44:14.939    W_Handle leads             schedule   User_1
2016-12-30 14:45:40.794    W_Handle leads             withdraw   User_1
2016-12-30 14:45:40.802    W_Complete application     schedule   User_1
2016-12-30 14:45:40.807    A_Concept                  complete   User_1
2017-01-02 09:06:43.901    W_Complete application     start      User_72
2017-01-02 09:14:15.212    A_Accepted                 complete   User_72
2017-01-02 09:18:17.628    O_Create Offer             complete   User_72
2017-01-02 09:18:18.253    O_Created                  complete   User_72
2017-01-02 09:20:23.510    O_Sent (mail and online)   complete   User_72
2017-01-02 09:20:23.522    W_Complete application     complete   User_72
2017-01-02 09:20:23.530    W_Call after offers        schedule   User_72
2017-01-02 09:20:23.532    W_Call after offers        start      User_72
2017-01-02 09:20:23.535    A_Complete                 complete   User_72
2017-01-02 09:24:14.063    W_Call after offers        suspend    User_72
2017-01-06 07:33:03.102    W_Call after offers        ate_abort  User_1
2017-01-06 07:33:03.108    W_Call after offers        schedule   User_1
```
