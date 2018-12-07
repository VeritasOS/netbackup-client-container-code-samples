
db = db.getSiblingDB('dummydb');
sh.enableSharding("dummydb");
sh.shardCollection("dummydb.dummyimage", {"_id" : "hashed"});
for (var i = 1; i <= 100000; i++) {
	db.dummyimage.insert([
		{
			field1: "dummy-field-1-" + i,
			field2: "dummy-field-2-" + i,
			field3: "dummy-field-3-" + i
		}])
};
