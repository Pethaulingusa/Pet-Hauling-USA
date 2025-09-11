import React, { useEffect, useState, useRef } from 'react';
import { View, Text, TextInput, Button, FlatList, KeyboardAvoidingView, Platform } from 'react-native';
import { authFetch } from '../../utils/api';

export default function ChatScreen({ route }){
  const { bidId } = route.params;
  const [msgs, setMsgs] = useState([]);
  const [text, setText] = useState('');
  const sinceRef = useRef(null);

  async function load(){
    const url = sinceRef.current ? `/chat/messages?bidId=${bidId}&since=${encodeURIComponent(sinceRef.current)}` : `/chat/messages?bidId=${bidId}`;
    const rows = await authFetch(url);
    if(rows.length){
      setMsgs(m => [...m, ...rows]);
      sinceRef.current = rows[rows.length-1].created_at;
    }
  }

  useEffect(() => {
    load();
    const t = setInterval(load, 3000);
    return () => clearInterval(t);
  }, [bidId]);

  async function send(){
    if(!text.trim()) return;
    const m = await authFetch('/chat/send', { method:'POST', body: JSON.stringify({ bidId, body: text })});
    setMsgs(arr => [...arr, m]);
    setText('');
  }

  const render = ({ item }) => (
    <View style={{ alignSelf: 'stretch', marginVertical: 6 }}>
      <Text style={{ fontWeight:'700' }}>{item.sender_user_id}</Text>
      <Text>{item.body}</Text>
      <Text style={{ color:'#888', fontSize:12 }}>{new Date(item.created_at).toLocaleTimeString()}</Text>
    </View>
  );

  return (
    <KeyboardAvoidingView style={{ flex:1 }} behavior={Platform.OS==='ios'?'padding':undefined}>
      <FlatList data={msgs} keyExtractor={x=>String(x.id)} renderItem={render} contentContainerStyle={{ padding:12 }} />
      <View style={{ flexDirection:'row', padding:8, borderTopWidth:1 }}>
        <TextInput style={{ flex:1, borderWidth:1, borderRadius:8, padding:8, marginRight:8 }} value={text} onChangeText={setText} placeholder="Message..." />
        <Button title="Send" onPress={send} />
      </View>
    </KeyboardAvoidingView>
  );
}
