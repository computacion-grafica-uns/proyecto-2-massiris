using UnityEngine;

public class LightController : MonoBehaviour
{
    [Header("Luces")]
    public Light directionalLight;
    public Light pointLight;
    public Light spotLight;

    void Update()
    {
        // Tecla 1 → activa/desactiva luz direccional
        if (Input.GetKeyDown(KeyCode.Alpha1))
            directionalLight.enabled = !directionalLight.enabled;

        // Tecla 2 → activa/desactiva luz puntual
        if (Input.GetKeyDown(KeyCode.Alpha2))
            pointLight.enabled = !pointLight.enabled;

        // Tecla 3 → activa/desactiva luz spot
        if (Input.GetKeyDown(KeyCode.Alpha3))
            spotLight.enabled = !spotLight.enabled;
    }

    // Métodos públicos útiles si después querés llamarlos desde una UI
    public void ToggleDirectional() => directionalLight.enabled = !directionalLight.enabled;
    public void TogglePoint()       => pointLight.enabled = !pointLight.enabled;
    public void ToggleSpot()        => spotLight.enabled = !spotLight.enabled;
}