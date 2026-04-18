exports.handler = async (event) => {
    const body = JSON.parse(event.body);
    const now = new Date().toISOString();

    // LOG 1: Recepción del evento (Requerimiento del profesor)
    console.log(`[RECIBIDO] Placa: ${body.vehicle_plate} | Tipo: ${body.type} | Hora: ${now}`);

    if (body.type === "Emergency") {
        // LOG 2: Simulación de envío de correo (Para asegurar los < 15 seg)
        const sendTime = new Date().toISOString();
        console.log(`[ALERTA-EMAIL] Enviando notificación para ${body.vehicle_plate} a las ${sendTime}`);

        // Aquí es donde iría la lógica de Nodemailer o SES que definiremos luego
    }

    return {
        statusCode: 200,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ 
            status: "Procesado", 
            timestamp: now 
        }),
    };
};